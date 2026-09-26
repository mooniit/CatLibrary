-- M2: immutable final records, durable checkpoints and cumulative daily rewards.
alter table public.wallet_entries drop constraint wallet_entries_kind_check;
alter table public.wallet_entries drop constraint wallet_entries_miao_delta_check;
alter table public.wallet_entries drop constraint wallet_entries_owner_id_kind_key;
alter table public.wallet_entries add column business_day date;
alter table public.wallet_entries add constraint wallet_entry_reward_shape check (
  (kind='initial' and miao_delta=30 and business_day is null) or
  (kind='study' and miao_delta>0 and miao_delta<=120 and business_day is not null)
);
create unique index wallet_initial_once on public.wallet_entries(owner_id) where kind='initial';

create table public.study_sessions (
  id uuid primary key,
  owner_id uuid not null references public.wallets(owner_id),
  started_at timestamptz not null,
  recorded_until timestamptz not null,
  confirmed boolean not null default false,
  check(recorded_until>=started_at and recorded_until<=started_at+interval '6 hours')
);
create index study_owner_time on public.study_sessions(owner_id,started_at);
create table public.study_days (
  owner_id uuid not null references public.wallets(owner_id),
  business_day date not null,
  eligible_ms bigint not null check(eligible_ms>=0),
  issued integer not null default 0 check(issued between 0 and 120),
  primary key(owner_id,business_day)
);
alter table public.study_sessions enable row level security;
alter table public.study_days enable row level security;
revoke all on public.study_sessions, public.study_days from anon, authenticated;
grant select on public.study_sessions, public.study_days to authenticated;
create policy own_study_read on public.study_sessions for select to authenticated
  using(owner_id=(select auth.uid()));
create policy own_study_days_read on public.study_days for select to authenticated
  using(owner_id=(select auth.uid()));

-- Internal: all paths serialize on the wallet, including the midnight worker.
create function public.settle_study_for_owner(target_owner uuid, as_of timestamptz)
returns void language plpgsql security definer set search_path='' as $$
declare
  day_row record;
  previous_issued integer;
  due integer;
  midnight timestamptz := ((as_of at time zone 'Asia/Shanghai')::date)::timestamp at time zone 'Asia/Shanghai';
begin
  perform 1 from public.wallets where owner_id=target_owner for update;
  if not found then raise exception 'Wallet missing'; end if;
  for day_row in
    with eligible as (
      select started_at, case when confirmed then recorded_until
        else least(recorded_until,midnight) end as until_at
      from public.study_sessions where owner_id=target_owner
    ), ranges as (
      select *, (started_at at time zone 'Asia/Shanghai')::date as first_day,
        ((until_at-interval '1 microsecond') at time zone 'Asia/Shanghai')::date as last_day
      from eligible where until_at>started_at
    ), segments as (
      select first_day+n as day,
        greatest(started_at,(first_day+n)::timestamp at time zone 'Asia/Shanghai') as a,
        least(until_at,(first_day+n+1)::timestamp at time zone 'Asia/Shanghai') as b
      from ranges cross join lateral generate_series(0,last_day-first_day) n
    )
    select day, sum(extract(epoch from (b-a))*1000)::bigint as ms
    from segments group by day order by day
  loop
    insert into public.study_days(owner_id,business_day,eligible_ms)
      values(target_owner,day_row.day,day_row.ms)
      on conflict(owner_id,business_day) do update set eligible_ms=excluded.eligible_ms;
    select issued into previous_issued from public.study_days
      where owner_id=target_owner and business_day=day_row.day;
    due := least(120,(day_row.ms/60000)*2)::integer;
    if due>previous_issued then
      update public.wallets set miao_coins=miao_coins+due-previous_issued where owner_id=target_owner;
      insert into public.wallet_entries(owner_id,kind,miao_delta,business_day)
        values(target_owner,'study',due-previous_issued,day_row.day);
      update public.study_days set issued=due where owner_id=target_owner and business_day=day_row.day;
    end if;
  end loop;
end;
$$;
revoke all on function public.settle_study_for_owner(uuid,timestamptz) from public,anon,authenticated;

create function public.study_state() returns jsonb
language plpgsql security definer set search_path='' as $$
declare current_owner uuid:=auth.uid(); result jsonb;
begin
  if current_owner is null then raise exception 'Authentication required' using errcode='42501'; end if;
  perform public.settle_study_for_owner(current_owner,clock_timestamp());
  select jsonb_build_object(
    'wallet',jsonb_build_object('owner_id',owner_id,'miao_coins',miao_coins,'eagle_pounds',eagle_pounds,'gems',gems),
    'days',coalesce((select jsonb_agg(jsonb_build_object('day',business_day,'eligible_ms',eligible_ms,'issued',issued) order by business_day)
      from public.study_days where owner_id=current_owner),'[]'::jsonb))
    into result from public.wallets where owner_id=current_owner;
  return result;
end;
$$;
revoke all on function public.study_state() from public,anon;
grant execute on function public.study_state() to authenticated;

create function public.sync_study_session(session_id uuid, start_at timestamptz,
  checkpoint_at timestamptz, is_confirmed boolean) returns jsonb
language plpgsql security definer set search_path='' as $$
declare current_owner uuid:=auth.uid(); previous public.study_sessions;
begin
  if current_owner is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if session_id is null or start_at is null or checkpoint_at is null or is_confirmed is null
    or not isfinite(start_at) or not isfinite(checkpoint_at)
    or checkpoint_at<start_at or checkpoint_at>start_at+interval '6 hours'
    or checkpoint_at>clock_timestamp()+interval '5 minutes' then
    raise exception 'Invalid study interval' using errcode='22023';
  end if;
  perform 1 from public.wallets where owner_id=current_owner for update;
  if not found then raise exception 'Wallet missing'; end if;
  select * into previous from public.study_sessions where id=session_id;
  if found then
    if previous.owner_id<>current_owner or previous.started_at<>start_at then
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
  insert into public.study_sessions(id,owner_id,started_at,recorded_until,confirmed)
    values(session_id,current_owner,start_at,checkpoint_at,is_confirmed)
    on conflict(id) do update set recorded_until=excluded.recorded_until,confirmed=excluded.confirmed;
  return public.study_state();
end;
$$;
revoke all on function public.sync_study_session(uuid,timestamptz,timestamptz,boolean) from public,anon;
grant execute on function public.sync_study_session(uuid,timestamptz,timestamptz,boolean) to authenticated;

-- Settles only evidence actually received, never extrapolates a sleeping device.
create function public.settle_study_midnight() returns void
language plpgsql security definer set search_path='' as $$
declare target uuid;
begin
  for target in select distinct owner_id from public.study_sessions order by owner_id loop
    perform public.settle_study_for_owner(target,clock_timestamp());
  end loop;
end;
$$;
revoke all on function public.settle_study_midnight() from public,anon,authenticated;
create extension if not exists pg_cron;
select cron.schedule('study-midnight','0 16 * * *','select public.settle_study_midnight()');
