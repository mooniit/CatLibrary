-- T34: one owner/date aggregate, available from 21:00 Beijing; never settles fees.
create table public.feeding_reminders (
  owner_id uuid not null references auth.users(id),
  business_day date not null,
  family_id uuid not null references public.families(id),
  cats jsonb not null check(jsonb_typeof(cats)='array' and jsonb_array_length(cats)>0),
  created_at timestamptz not null,
  in_app_seen_at timestamptz,
  notification_seen_at timestamptz,
  primary key(owner_id,business_day)
);
alter table public.feeding_reminders enable row level security;
revoke all on public.feeding_reminders from public,anon,authenticated;
grant select on public.feeding_reminders to authenticated;
create policy owner_reminder_read on public.feeding_reminders for select to authenticated
  using(owner_id=(select auth.uid()));

-- Only the zero-argument public wrapper may supply time for client requests.
-- The owner comes from the session in both the helper and its wrapper.
create function public.feeding_reminder_at(as_of timestamptz) returns jsonb
language plpgsql security definer set search_path='' as $$
declare me uuid:=auth.uid(); home uuid; day_begin timestamptz; day_end timestamptz;
  today date; eligible jsonb; prior public.feeding_reminders; result_cats jsonb;
begin
  if me is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if as_of is null or not isfinite(as_of) then
    raise exception 'Invalid reminder time' using errcode='22023'; end if;
  today:=(as_of at time zone 'Asia/Shanghai')::date;
  if (as_of at time zone 'Asia/Shanghai')::time<time '21:00' then
    return jsonb_build_object('status','before_time','business_day',today);
  end if;
  select family_id into home from public.family_members where user_id=me;
  if home is null then return jsonb_build_object('status','empty','business_day',today); end if;
  -- Serialize with feeding and travel. Reading reminders never changes a wallet.
  perform 1 from public.families where id=home for update;
  if not exists(select 1 from public.family_members where user_id=me and family_id=home)
      or exists(select 1 from public.repair_episodes where family_id=home
        and (status in ('pending','active') or (status='completed' and grace_through>=today))) then
    return jsonb_build_object('status','empty','business_day',today);
  end if;
  day_begin:=today::timestamp at time zone 'Asia/Shanghai';
  day_end:=(today+1)::timestamp at time zone 'Asia/Shanghai';
  select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'name',c.name)
    order by c.adopted_at,c.id),'[]'::jsonb) into eligible
    from public.cats c where c.owner_id=me and c.family_id=home
      and not exists(select 1 from public.cat_feedings f
        where f.cat_id=c.id and f.business_day=today)
      -- Match the automatic fee exemption even if a trip already returned today.
      and not exists(select 1 from public.cat_trips t where t.cat_id=c.id
        and t.started_at<day_end and t.ends_at>day_begin);
  if jsonb_array_length(eligible)=0 then
    return jsonb_build_object('status','empty','business_day',today);
  end if;
  insert into public.feeding_reminders(owner_id,business_day,family_id,cats,created_at)
    values(me,today,home,eligible,as_of) on conflict(owner_id,business_day) do nothing;
  select * into strict prior from public.feeding_reminders
    where owner_id=me and business_day=today;
  -- A second read can remove fed/traveling cats; it cannot add another reminder.
  select coalesce(jsonb_agg(e.value order by e.ordinality),'[]'::jsonb) into result_cats
    from jsonb_array_elements(eligible) with ordinality e(value,ordinality)
    where prior.family_id=home and exists(
      select 1 from jsonb_array_elements(prior.cats) original
      where original->>'id'=e.value->>'id');
  if jsonb_array_length(result_cats)=0 then
    return jsonb_build_object('status','empty','business_day',today);
  end if;
  return jsonb_build_object('status','ready','owner_id',me,'family_id',home,
    'business_day',today,'cats',result_cats,'created_at',prior.created_at,
    'in_app_seen',prior.in_app_seen_at is not null,
    'notification_seen',prior.notification_seen_at is not null);
end; $$;
revoke all on function public.feeding_reminder_at(timestamptz) from public,anon,authenticated;

create function public.get_feeding_reminder() returns jsonb
language sql security definer set search_path='' as $$
  select public.feeding_reminder_at(clock_timestamp());
$$;
revoke all on function public.get_feeding_reminder() from public,anon;
grant execute on function public.get_feeding_reminder() to authenticated;

create function public.ack_feeding_reminder(target_day date,target_channel text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare me uuid:=auth.uid(); changed integer;
begin
  if me is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if target_day is null or target_channel is null
      or target_channel not in ('in_app','notification') then
    raise exception 'Invalid reminder acknowledgment' using errcode='22023'; end if;
  update public.feeding_reminders set
    in_app_seen_at=case when target_channel='in_app'
      then coalesce(in_app_seen_at,clock_timestamp()) else in_app_seen_at end,
    notification_seen_at=case when target_channel='notification'
      then coalesce(notification_seen_at,clock_timestamp()) else notification_seen_at end
    where owner_id=me and business_day=target_day;
  get diagnostics changed=row_count;
  return jsonb_build_object('status',case when changed=0 then 'not_found' else 'acknowledged' end,
    'owner_id',me,'business_day',target_day,'channel',target_channel);
end; $$;
revoke all on function public.ack_feeding_reminder(date,text) from public,anon;
grant execute on function public.ack_feeding_reminder(date,text) to authenticated;
