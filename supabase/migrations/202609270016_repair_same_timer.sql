-- Q09: an ongoing timer that finishes repair remains repair-only through its end.
-- T21: time inside a started repair episode earns repair progress, never currency.
create function public.rewardable_ms(target_owner uuid, session_started_at timestamptz,
  start_at timestamptz, end_at timestamptz) returns bigint
language sql stable security definer set search_path='' as $$
  select case when end_at<=start_at then 0 else greatest(0,
    (extract(epoch from end_at-start_at)*1000)::bigint-
    coalesce((select sum(greatest(0,
      (extract(epoch from least(end_at,case when e.status='completed' and session_started_at<e.completed_at
          then end_at else coalesce(e.completed_at,end_at) end)
        -greatest(start_at,w.starts_at))*1000)::bigint))
      from public.repair_episodes e
      join (select episode_id,min(starts_at) as starts_at
        from public.repair_windows group by episode_id) w on w.episode_id=e.id
      join public.family_members m on m.family_id=e.family_id
      where m.user_id=target_owner and e.status in ('active','completed')
        and w.starts_at<end_at
        and (e.status<>'completed' or session_started_at<e.completed_at
          or e.completed_at>start_at)),0)) end;
$$;
revoke all on function public.rewardable_ms(uuid,timestamptz,timestamptz,timestamptz)
  from public,anon,authenticated;

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
      select started_at,case when confirmed then least(recorded_until,as_of)
        else least(recorded_until,midnight,as_of) end as until_at
      from public.study_sessions where owner_id=target_owner
    ), ranges as (
      select *, (started_at at time zone 'Asia/Shanghai')::date as first_day,
        ((until_at-interval '1 microsecond') at time zone 'Asia/Shanghai')::date as last_day
      from eligible where until_at>started_at
    ), segments as (
      select started_at,first_day+n as day,
        greatest(started_at,(first_day+n)::timestamp at time zone 'Asia/Shanghai') as a,
        least(until_at,(first_day+n+1)::timestamp at time zone 'Asia/Shanghai') as b
      from ranges cross join lateral generate_series(0,last_day-first_day) n
    )
    select day,sum(public.rewardable_ms(target_owner,started_at,a,b))::bigint as ms
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

create or replace function public.settle_tasks_for_owner(target_owner uuid)
returns void language plpgsql security definer set search_path='' as $$
declare day_row record; previous_issued integer; due integer;
begin
  perform 1 from public.wallets where owner_id=target_owner for update;
  if not found then raise exception 'Wallet missing'; end if;
  for day_row in
    with ranges as (
      select activity,started_at,recorded_until,
        (started_at at time zone 'Asia/Shanghai')::date as first_day,
        ((recorded_until-interval '1 microsecond') at time zone 'Asia/Shanghai')::date as last_day
      from public.task_sessions where owner_id=target_owner
        and confirmed and recorded_until>started_at
    ), segments as (
      select activity,started_at,first_day+n as day,
        greatest(started_at,(first_day+n)::timestamp at time zone 'Asia/Shanghai') as a,
        least(recorded_until,(first_day+n+1)::timestamp at time zone 'Asia/Shanghai') as b
      from ranges cross join lateral generate_series(0,last_day-first_day) n
    )
    select activity,day,sum(public.rewardable_ms(target_owner,started_at,a,b))::bigint as ms
      from segments group by activity,day order by day,activity
  loop
    insert into public.task_days(owner_id,activity,business_day,eligible_ms)
      values(target_owner,day_row.activity,day_row.day,day_row.ms)
      on conflict(owner_id,activity,business_day)
        do update set eligible_ms=excluded.eligible_ms;
    select issued into previous_issued from public.task_days
      where owner_id=target_owner and activity=day_row.activity
        and business_day=day_row.day;
    due:=case when day_row.ms>=600000
      then least(12,(day_row.ms/300000)::integer) else 0 end;
    if due>previous_issued then
      if day_row.activity='language' then
        update public.wallets set eagle_pounds=eagle_pounds+due-previous_issued
          where owner_id=target_owner;
        insert into public.wallet_entries
          (owner_id,kind,miao_delta,eagle_delta,business_day)
          values(target_owner,'task_language',0,due-previous_issued,day_row.day);
      else
        update public.wallets set gems=gems+due-previous_issued
          where owner_id=target_owner;
        insert into public.wallet_entries
          (owner_id,kind,miao_delta,gem_delta,business_day)
          values(target_owner,'task_exercise',0,due-previous_issued,day_row.day);
      end if;
      update public.task_days set issued=due where owner_id=target_owner
        and activity=day_row.activity and business_day=day_row.day;
    end if;
  end loop;
end; $$;

drop function public.rewardable_ms(uuid,timestamptz,timestamptz);
