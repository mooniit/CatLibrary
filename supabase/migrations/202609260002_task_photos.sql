-- M3 T14: private photo evidence and separately accumulated activity rewards.
alter table public.wallet_entries add column eagle_delta integer not null default 0;
alter table public.wallet_entries add column gem_delta integer not null default 0;
alter table public.wallet_entries drop constraint wallet_entry_reward_shape;
alter table public.wallet_entries add constraint wallet_entry_reward_shape check (
  (kind='initial' and miao_delta=30 and eagle_delta=0 and gem_delta=0 and business_day is null) or
  (kind='study' and miao_delta>0 and miao_delta<=120 and eagle_delta=0 and gem_delta=0 and business_day is not null) or
  (kind='task_language' and miao_delta=0 and eagle_delta between 1 and 12 and gem_delta=0 and business_day is not null) or
  (kind='task_exercise' and miao_delta=0 and eagle_delta=0 and gem_delta between 1 and 12 and business_day is not null)
);

create table public.task_sessions (
  id uuid primary key,
  owner_id uuid not null references public.wallets(owner_id),
  activity text not null check(activity in ('language','exercise')),
  started_at timestamptz not null,
  recorded_until timestamptz not null,
  photo_path text,
  confirmed boolean not null default false,
  check(recorded_until>=started_at and recorded_until<=started_at+interval '6 hours'),
  check(not confirmed or photo_path is not null)
);
create index task_owner_time on public.task_sessions(owner_id,started_at);
create table public.task_days (
  owner_id uuid not null references public.wallets(owner_id),
  activity text not null check(activity in ('language','exercise')),
  business_day date not null,
  eligible_ms bigint not null check(eligible_ms>=0),
  issued integer not null default 0 check(issued between 0 and 12),
  primary key(owner_id,activity,business_day)
);
alter table public.task_sessions enable row level security;
alter table public.task_days enable row level security;
revoke all on public.task_sessions, public.task_days from anon, authenticated;
grant select on public.task_sessions, public.task_days to authenticated;
create policy own_task_read on public.task_sessions for select to authenticated
  using(owner_id=(select auth.uid()));
create policy own_task_days_read on public.task_days for select to authenticated
  using(owner_id=(select auth.uid()));

-- Study and task RPCs both lock the owner's wallet before writing. The trigger
-- closes the gap between the two record tables without changing M2's RPC.
create function public.reject_cross_activity_overlap() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if tg_table_name='task_sessions' then
    if exists(select 1 from public.study_sessions s where s.owner_id=new.owner_id
      and s.started_at<new.recorded_until and s.recorded_until>new.started_at) then
      raise exception 'Overlapping study interval' using errcode='22023';
    end if;
  elsif exists(select 1 from public.task_sessions t where t.owner_id=new.owner_id
    and t.started_at<new.recorded_until and t.recorded_until>new.started_at) then
    raise exception 'Overlapping task interval' using errcode='22023';
  end if;
  return new;
end;
$$;
revoke all on function public.reject_cross_activity_overlap() from public, anon, authenticated;
create trigger task_cross_overlap before insert or update of owner_id,started_at,recorded_until
  on public.task_sessions for each row execute function public.reject_cross_activity_overlap();
create trigger study_cross_overlap before insert or update of owner_id,started_at,recorded_until
  on public.study_sessions for each row execute function public.reject_cross_activity_overlap();

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
  values('task-photos','task-photos',false,5242880,array['image/jpeg','image/png'])
  on conflict(id) do nothing;

create function public.task_photo_visible(object_name text) returns boolean
language sql stable security definer set search_path='' as $$
  select (select auth.uid())::text=split_part(object_name,'/',1) or exists (
    select 1 from public.task_sessions t
      join public.family_members a on a.user_id=t.owner_id
      join public.family_members b on b.family_id=a.family_id
    where t.confirmed and t.photo_path=object_name and b.user_id=(select auth.uid())
  );
$$;
revoke all on function public.task_photo_visible(text) from public, anon;
grant execute on function public.task_photo_visible(text) to authenticated;
create policy task_photo_insert on storage.objects for insert to authenticated
  with check(bucket_id='task-photos' and name=auth.uid()::text||'/'||split_part(name,'/',2)
    and exists(select 1 from public.task_sessions t where t.id::text=split_part(name,'/',2)
      and t.owner_id=auth.uid() and not t.confirmed));
create policy task_photo_select on storage.objects for select to authenticated
  using(bucket_id='task-photos' and public.task_photo_visible(name));

create function public.settle_tasks_for_owner(target_owner uuid) returns void
language plpgsql security definer set search_path='' as $$
declare day_row record; previous_issued integer; due integer;
begin
  perform 1 from public.wallets where owner_id=target_owner for update;
  if not found then raise exception 'Wallet missing'; end if;
  for day_row in
    with ranges as (
      select activity, started_at, recorded_until,
        (started_at at time zone 'Asia/Shanghai')::date as first_day,
        ((recorded_until-interval '1 microsecond') at time zone 'Asia/Shanghai')::date as last_day
      from public.task_sessions where owner_id=target_owner and confirmed and recorded_until>started_at
    ), segments as (
      select activity, first_day+n as day,
        greatest(started_at,(first_day+n)::timestamp at time zone 'Asia/Shanghai') as a,
        least(recorded_until,(first_day+n+1)::timestamp at time zone 'Asia/Shanghai') as b
      from ranges cross join lateral generate_series(0,last_day-first_day) n
    )
    select activity,day,sum(extract(epoch from (b-a))*1000)::bigint as ms
      from segments group by activity,day order by day,activity
  loop
    insert into public.task_days(owner_id,activity,business_day,eligible_ms)
      values(target_owner,day_row.activity,day_row.day,day_row.ms)
      on conflict(owner_id,activity,business_day) do update set eligible_ms=excluded.eligible_ms;
    select issued into previous_issued from public.task_days
      where owner_id=target_owner and activity=day_row.activity and business_day=day_row.day;
    due := case when day_row.ms>=600000 then least(12,(day_row.ms/300000)::integer) else 0 end;
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
end;
$$;
revoke all on function public.settle_tasks_for_owner(uuid) from public,anon,authenticated;

create function public.task_state() returns jsonb
language plpgsql security definer set search_path='' as $$
declare me uuid:=auth.uid(); result jsonb;
begin
  if me is null then raise exception 'Authentication required' using errcode='42501'; end if;
  select jsonb_build_object(
    'wallet',jsonb_build_object('owner_id',owner_id,'miao_coins',miao_coins,
      'eagle_pounds',eagle_pounds,'gems',gems),
    'days',coalesce((select jsonb_agg(jsonb_build_object('activity',activity,
      'day',business_day,'eligible_ms',eligible_ms,'issued',issued) order by business_day,activity)
      from public.task_days where owner_id=me),'[]'::jsonb))
    into result from public.wallets where owner_id=me;
  return result;
end;
$$;
revoke all on function public.task_state() from public,anon;
grant execute on function public.task_state() to authenticated;

create function public.sync_task_session(session_id uuid, task_activity text,
  start_at timestamptz, checkpoint_at timestamptz, task_photo_path text,
  is_confirmed boolean) returns jsonb
language plpgsql security definer set search_path='' as $$
declare me uuid:=auth.uid(); previous public.task_sessions; expected_path text;
begin
  if me is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if session_id is null or task_activity not in ('language','exercise')
    or start_at is null or checkpoint_at is null or is_confirmed is null
    or not isfinite(start_at) or not isfinite(checkpoint_at)
    or checkpoint_at<start_at or checkpoint_at>start_at+interval '6 hours'
    or checkpoint_at>clock_timestamp()+interval '5 minutes' then
    raise exception 'Invalid task interval' using errcode='22023';
  end if;
  expected_path := me::text||'/'||session_id::text;
  if task_photo_path is not null and task_photo_path<>expected_path then
    raise exception 'Invalid photo path' using errcode='22023';
  end if;
  if is_confirmed and task_photo_path is distinct from expected_path then
    raise exception 'Photo required before confirmation' using errcode='22023';
  end if;
  perform 1 from public.wallets where owner_id=me for update;
  if not found then raise exception 'Wallet missing'; end if;
  select * into previous from public.task_sessions where id=session_id;
  if found then
    if previous.owner_id<>me or previous.activity<>task_activity or previous.started_at<>start_at then
      raise exception 'Task identity mismatch' using errcode='42501';
    end if;
    if previous.confirmed and (checkpoint_at<>previous.recorded_until
      or task_photo_path is distinct from previous.photo_path or not is_confirmed) then
      raise exception 'Confirmed task is immutable' using errcode='22023';
    end if;
    checkpoint_at := greatest(checkpoint_at,previous.recorded_until);
  end if;
  if exists(select 1 from public.task_sessions t where t.owner_id=me and t.id<>session_id
    and t.started_at<checkpoint_at and t.recorded_until>start_at) then
    raise exception 'Overlapping task interval' using errcode='22023';
  end if;
  if is_confirmed and not exists(select 1 from storage.objects
    where bucket_id='task-photos' and name=expected_path) then
    raise exception 'Photo upload is not complete' using errcode='22023';
  end if;
  insert into public.task_sessions(id,owner_id,activity,started_at,recorded_until,photo_path,confirmed)
    values(session_id,me,task_activity,start_at,checkpoint_at,task_photo_path,is_confirmed)
    on conflict(id) do update set recorded_until=excluded.recorded_until,
      photo_path=excluded.photo_path,confirmed=excluded.confirmed;
  if is_confirmed then perform public.settle_tasks_for_owner(me); end if;
  return public.task_state();
end;
$$;
revoke all on function public.sync_task_session(uuid,text,timestamptz,timestamptz,text,boolean) from public,anon;
grant execute on function public.sync_task_session(uuid,text,timestamptz,timestamptz,text,boolean) to authenticated;

create function public.task_feed() returns jsonb
language sql stable security definer set search_path='' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'owner_id',t.owner_id,
    'activity',t.activity,'started_at',t.started_at,'recorded_until',t.recorded_until,
    'photo_path',t.photo_path) order by t.started_at desc),'[]'::jsonb)
  from public.task_sessions t
  where t.confirmed and (t.owner_id=(select auth.uid()) or exists(
    select 1 from public.family_members a join public.family_members b on b.family_id=a.family_id
    where a.user_id=t.owner_id and b.user_id=(select auth.uid())));
$$;
revoke all on function public.task_feed() from public,anon;
grant execute on function public.task_feed() to authenticated;
