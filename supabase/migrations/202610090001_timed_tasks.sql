-- 2026-10-09: regular tasks use timer evidence; historical photos stay private.
create table public.task_timer_runs (
  id uuid primary key,
  owner_id uuid not null references public.wallets(owner_id),
  activity text not null check (activity in ('language','exercise')),
  started_at timestamptz not null
);
alter table public.task_timer_runs enable row level security;
revoke all on public.task_timer_runs from public, anon, authenticated;
grant select on public.task_timer_runs to authenticated;
create policy own_task_run_read on public.task_timer_runs for select to authenticated
  using (owner_id=(select auth.uid()));
alter table public.task_sessions add column run_id uuid references public.task_timer_runs(id);
alter table public.task_sessions add column run_started_at timestamptz;
alter table public.task_sessions add column timer_running boolean not null default false;
alter table public.task_sessions drop constraint task_sessions_check1;
alter table public.task_sessions add constraint task_confirmation_evidence
  check (not confirmed or photo_path is not null or run_id is not null);
alter table public.task_sessions add constraint task_run_interval
  check ((run_id is null and run_started_at is null) or
    (run_id is not null and run_started_at is not null and started_at>=run_started_at
      and recorded_until<=run_started_at+interval '6 hours'));

create function public.sync_timed_task_session(session_id uuid, task_activity text,
  start_at timestamptz, checkpoint_at timestamptz, is_confirmed boolean,
  timer_run_id uuid, run_start_at timestamptz, is_running boolean) returns jsonb
language plpgsql security definer set search_path='' as $$
declare me uuid:=auth.uid(); previous public.task_sessions; timer public.task_timer_runs;
begin
  if me is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if session_id is null or timer_run_id is null or task_activity is null
    or task_activity not in ('language','exercise') or start_at is null
    or checkpoint_at is null or run_start_at is null or is_confirmed is null or is_running is null
    or (is_confirmed and is_running)
    or not isfinite(start_at) or not isfinite(checkpoint_at) or not isfinite(run_start_at)
    or start_at<run_start_at or checkpoint_at<start_at
    or checkpoint_at>run_start_at+interval '6 hours'
    or checkpoint_at>clock_timestamp()+interval '5 minutes' then
    raise exception 'Invalid timed task interval' using errcode='22023';
  end if;
  perform 1 from public.wallets where owner_id=me for update;
  if not found then raise exception 'Wallet missing'; end if;
  insert into public.task_timer_runs(id,owner_id,activity,started_at)
    values(timer_run_id,me,task_activity,run_start_at) on conflict(id) do nothing;
  select * into timer from public.task_timer_runs where id=timer_run_id for update;
  if timer.owner_id<>me or timer.activity<>task_activity or timer.started_at<>run_start_at then
    raise exception 'Timer identity mismatch' using errcode='42501';
  end if;
  select * into previous from public.task_sessions where id=session_id;
  if found then
    if previous.owner_id<>me or previous.activity<>task_activity or previous.started_at<>start_at
      or previous.photo_path is not null
      or (previous.run_id is not null and (previous.run_id<>timer_run_id or previous.run_started_at<>run_start_at))
      or (previous.run_id is null and (timer_run_id<>session_id or run_start_at<>start_at)) then
      raise exception 'Task identity mismatch' using errcode='42501';
    end if;
    if previous.confirmed then
      if checkpoint_at<>previous.recorded_until then
        raise exception 'Confirmed task is immutable' using errcode='22023';
      end if;
      -- A lost confirmation receipt may retry an earlier, unconfirmed request.
      return public.task_state();
    end if;
    if previous.run_id is not null and not previous.timer_running and is_running then
      raise exception 'Stopped segment cannot resume' using errcode='22023';
    end if;
    checkpoint_at:=greatest(checkpoint_at,previous.recorded_until);
  end if;
  if exists(select 1 from public.task_sessions where owner_id=me and id<>session_id
    and started_at<checkpoint_at and recorded_until>start_at) then
    raise exception 'Overlapping task interval' using errcode='22023';
  end if;
  insert into public.task_sessions(id,owner_id,activity,started_at,recorded_until,confirmed,run_id,run_started_at,timer_running)
    values(session_id,me,task_activity,start_at,checkpoint_at,is_confirmed,timer_run_id,run_start_at,is_running)
    on conflict(id) do update set recorded_until=excluded.recorded_until,
      confirmed=excluded.confirmed,run_id=excluded.run_id,run_started_at=excluded.run_started_at,timer_running=excluded.timer_running;
  perform public.settle_tasks_for_owner(me);
  return public.task_state();
end; $$;
revoke all on function public.sync_timed_task_session(uuid,text,timestamptz,timestamptz,boolean,uuid,timestamptz,boolean)
  from public,anon;
grant execute on function public.sync_timed_task_session(uuid,text,timestamptz,timestamptz,boolean,uuid,timestamptz,boolean)
  to authenticated;

create or replace function public.settle_tasks_for_owner(target_owner uuid)
returns void language plpgsql security definer set search_path='' as $$
declare day_row record; previous_issued integer; due integer;
  midnight timestamptz:=(clock_timestamp() at time zone 'Asia/Shanghai')::date::timestamp at time zone 'Asia/Shanghai';
begin
  perform 1 from public.wallets where owner_id=target_owner for update;
  if not found then raise exception 'Wallet missing'; end if;
  for day_row in
    with eligible as (
      select activity,started_at,coalesce(run_started_at,started_at) as run_start,
        case when confirmed then recorded_until else least(recorded_until,midnight) end as until_at
      from public.task_sessions where owner_id=target_owner and (confirmed or (run_id is not null and timer_running))
    ), ranges as (
      select *, (started_at at time zone 'Asia/Shanghai')::date as first_day,
        ((until_at-interval '1 microsecond') at time zone 'Asia/Shanghai')::date as last_day
      from eligible where until_at>started_at
    ), segments as (
      select activity,run_start,first_day+n as day,
        greatest(started_at,(first_day+n)::timestamp at time zone 'Asia/Shanghai') as a,
        least(until_at,(first_day+n+1)::timestamp at time zone 'Asia/Shanghai') as b
      from ranges cross join lateral generate_series(0,last_day-first_day) n
    )
    select activity,day,sum(public.rewardable_ms(target_owner,run_start,a,b))::bigint as ms
      from segments group by activity,day order by day,activity
  loop
    insert into public.task_days(owner_id,activity,business_day,eligible_ms)
      values(target_owner,day_row.activity,day_row.day,day_row.ms)
      on conflict(owner_id,activity,business_day) do update set eligible_ms=excluded.eligible_ms;
    select issued into previous_issued from public.task_days where owner_id=target_owner
      and activity=day_row.activity and business_day=day_row.day;
    due:=case when day_row.ms>=600000 then least(12,(day_row.ms/300000)::integer) else 0 end;
    if due>previous_issued then
      if day_row.activity='language' then
        update public.wallets set eagle_pounds=eagle_pounds+due-previous_issued where owner_id=target_owner;
        insert into public.wallet_entries(owner_id,kind,miao_delta,eagle_delta,business_day)
          values(target_owner,'task_language',0,due-previous_issued,day_row.day);
      else
        update public.wallets set gems=gems+due-previous_issued where owner_id=target_owner;
        insert into public.wallet_entries(owner_id,kind,miao_delta,gem_delta,business_day)
          values(target_owner,'task_exercise',0,due-previous_issued,day_row.day);
      end if;
      update public.task_days set issued=due where owner_id=target_owner
        and activity=day_row.activity and business_day=day_row.day;
    end if;
  end loop;
end; $$;
