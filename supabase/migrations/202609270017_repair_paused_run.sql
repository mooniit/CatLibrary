-- Q09: paused study intervals retain their logical timer identity.
alter table public.study_sessions add column run_id uuid;
update public.study_sessions set run_id=id;

create or replace function public.settle_study_for_owner(target_owner uuid,
  as_of timestamptz) returns void
language plpgsql security definer set search_path='' as $$
declare day_row record; previous_issued integer; due integer;
  midnight timestamptz:=((as_of at time zone 'Asia/Shanghai')::date)::timestamp
    at time zone 'Asia/Shanghai';
begin
  perform 1 from public.wallets where owner_id=target_owner for update;
  if not found then raise exception 'Wallet missing'; end if;
  for day_row in
    with eligible as (
      select started_at,min(started_at) over
        (partition by coalesce(run_id,id)) as run_started_at,
        case when confirmed then least(recorded_until,as_of)
        else least(recorded_until,midnight,as_of) end as until_at
      from public.study_sessions where owner_id=target_owner
    ), ranges as (
      select *, (started_at at time zone 'Asia/Shanghai')::date as first_day,
        ((until_at-interval '1 microsecond') at time zone 'Asia/Shanghai')::date as last_day
      from eligible where until_at>started_at
    ), segments as (
      select run_started_at,first_day+n as day,
        greatest(started_at,(first_day+n)::timestamp at time zone 'Asia/Shanghai') as a,
        least(until_at,(first_day+n+1)::timestamp at time zone 'Asia/Shanghai') as b
      from ranges cross join lateral generate_series(0,last_day-first_day) n
    )
    select day,sum(public.rewardable_ms(target_owner,run_started_at,a,b))::bigint as ms
      from segments group by day order by day
  loop
    insert into public.study_days(owner_id,business_day,eligible_ms)
      values(target_owner,day_row.day,day_row.ms)
      on conflict(owner_id,business_day) do update set eligible_ms=excluded.eligible_ms;
    select issued into previous_issued from public.study_days
      where owner_id=target_owner and business_day=day_row.day;
    due:=least(120,(day_row.ms/60000)*2)::integer;
    if due>previous_issued then
      update public.wallets set miao_coins=miao_coins+due-previous_issued
        where owner_id=target_owner;
      insert into public.wallet_entries(owner_id,kind,miao_delta,business_day)
        values(target_owner,'study',due-previous_issued,day_row.day);
      update public.study_days set issued=due
        where owner_id=target_owner and business_day=day_row.day;
    end if;
  end loop;
end; $$;

create function public.sync_study_run_session(session_id uuid, start_at timestamptz,
  checkpoint_at timestamptz, is_confirmed boolean, timer_run_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare current_owner uuid:=auth.uid(); previous public.study_sessions;
begin
  if current_owner is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if timer_run_id is null or session_id is null or start_at is null or checkpoint_at is null or is_confirmed is null
    or not isfinite(start_at) or not isfinite(checkpoint_at)
    or checkpoint_at<start_at or checkpoint_at>start_at+interval '6 hours'
    or checkpoint_at>clock_timestamp()+interval '5 minutes' then
    raise exception 'Invalid study interval' using errcode='22023';
  end if;
  perform 1 from public.wallets where owner_id=current_owner for update;
  if not found then raise exception 'Wallet missing'; end if;
  select * into previous from public.study_sessions where id=session_id;
  if found then
    if previous.owner_id<>current_owner or previous.started_at<>start_at
      or coalesce(previous.run_id,previous.id)<>timer_run_id then
      raise exception 'Session identity mismatch' using errcode='42501';
    end if;
    if previous.confirmed and (checkpoint_at<>previous.recorded_until or not is_confirmed) then
      raise exception 'Confirmed session is immutable' using errcode='22023';
    end if;
    -- A delayed checkpoint cannot roll evidence backwards.
    checkpoint_at := greatest(checkpoint_at,previous.recorded_until);
  end if;
  if exists(select 1 from public.study_sessions where owner_id=current_owner and id<>session_id
    and started_at<checkpoint_at and recorded_until>start_at) then
    raise exception 'Overlapping study interval' using errcode='22023';
  end if;
  insert into public.study_sessions(id,owner_id,started_at,recorded_until,confirmed,run_id)
    values(session_id,current_owner,start_at,checkpoint_at,is_confirmed,timer_run_id)
    on conflict(id) do update set recorded_until=excluded.recorded_until,
      confirmed=excluded.confirmed,run_id=excluded.run_id;
  return public.study_state();
end;
$$;
revoke all on function public.sync_study_run_session(uuid,timestamptz,timestamptz,boolean,uuid)
  from public,anon;
grant execute on function public.sync_study_run_session(uuid,timestamptz,timestamptz,boolean,uuid)
  to authenticated;
