-- Personal Monday 00:00 Beijing rotation. Draw history lives in offers.
create function public.weekly_ensure_personal(target_owner uuid, as_of timestamptz)
returns void language plpgsql security definer set search_path='' as $$
declare week_day date; batch uuid:=gen_random_uuid(); cycle integer;
  selected_id text; previous_this_week text; slot_index integer;
begin
  if target_owner is null or as_of is null then
    raise exception 'Invalid weekly draw' using errcode='22023';
  end if;
  week_day := (as_of at time zone 'Asia/Shanghai')::date;
  week_day := week_day-(extract(isodow from week_day)::integer-1);
  perform 1 from public.wallets where owner_id=target_owner for update;
  if not found then raise exception 'Wallet missing' using errcode='22023'; end if;
  if exists(select 1 from public.weekly_task_offers
    where owner_id=target_owner and week_start=week_day) then return; end if;
  if (select count(*) from public.weekly_task_catalog)<2 then
    raise exception 'At least two weekly tasks required' using errcode='22023';
  end if;
  select coalesce(max(cycle_no),1) into cycle from public.weekly_task_offers
    where owner_id=target_owner;
  for slot_index in 0..1 loop
    select t.id into selected_id from public.weekly_task_catalog t
      where not exists(select 1 from public.weekly_task_offers o
        where o.owner_id=target_owner and o.cycle_no=cycle and o.task_id=t.id)
      and t.id is distinct from previous_this_week
      order by random() limit 1;
    if selected_id is null then
      cycle := cycle+1;
      select t.id into selected_id from public.weekly_task_catalog t
        where t.id is distinct from previous_this_week order by random() limit 1;
    end if;
    insert into public.weekly_task_offers
      (id,owner_id,batch_id,week_start,cycle_no,slot,task_id,published_at)
      values(gen_random_uuid(),target_owner,batch,week_day,cycle,slot_index,selected_id,as_of);
    previous_this_week := selected_id;
  end loop;
end;
$$;
revoke all on function public.weekly_ensure_personal(uuid,timestamptz)
  from public,anon,authenticated;

create or replace function public.weekly_my_tasks() returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare me uuid:=auth.uid(); week_day date; result jsonb;
begin
  if me is null then raise exception 'Authentication required' using errcode='42501'; end if;
  perform public.weekly_ensure_personal(me,clock_timestamp());
  week_day := (clock_timestamp() at time zone 'Asia/Shanghai')::date;
  week_day := week_day-(extract(isodow from week_day)::integer-1);
  select coalesce(jsonb_agg(jsonb_build_object(
    'offer_id',o.id,'batch_id',o.batch_id,'week_start',o.week_start,
    'task_id',t.id,'prompt',t.prompt,'evidence_kind',t.evidence_kind,
    'image_count',t.image_count,'published_at',o.published_at,
    'confirmed_at',c.confirmed_at,'note',c.note,
    'photo_paths',coalesce(to_jsonb(c.photo_paths),'[]'::jsonb),
    'reward_status',case when c.confirmed_at is null then null else 'credited' end
  ) order by o.slot),'[]'::jsonb) into result
  from public.weekly_task_offers o
    join public.weekly_task_catalog t on t.id=o.task_id
    left join public.weekly_task_completions c on c.offer_id=o.id
  where o.owner_id=me and o.week_start=week_day;
  return result;
end;
$$;

-- A refreshed task can be viewed in history, but only the current week can be completed.
create or replace function public.weekly_offer_is_current(target_offer uuid, target_owner uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.weekly_task_offers o
    where o.id=target_offer and o.owner_id=target_owner
      and o.week_start=(clock_timestamp() at time zone 'Asia/Shanghai')::date
        -(extract(isodow from clock_timestamp() at time zone 'Asia/Shanghai')::integer-1));
$$;
revoke all on function public.weekly_offer_is_current(uuid,uuid)
  from public,anon,authenticated;

create function public.reject_expired_weekly_completion() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if not public.weekly_offer_is_current(new.offer_id,new.owner_id) then
    raise exception 'Weekly task has expired' using errcode='22023';
  end if;
  return new;
end;
$$;
revoke all on function public.reject_expired_weekly_completion()
  from public,anon,authenticated;
create trigger weekly_completion_current before insert or update
  on public.weekly_task_completions for each row
  execute function public.reject_expired_weekly_completion();

create or replace function public.weekly_photo_writable(object_name text) returns boolean
language sql stable security definer set search_path='' as $$
  select exists (
    select 1 from public.weekly_task_completions c
      join public.weekly_task_offers o on o.id=c.offer_id and o.owner_id=c.owner_id
      join public.weekly_task_catalog t on t.id=o.task_id
    where c.owner_id=(select auth.uid()) and c.confirmed_at is null
      and public.weekly_offer_is_current(o.id,o.owner_id)
      and o.id::text=split_part(object_name,'/',2)
      and split_part(object_name,'/',3) ~ '^[01]$'
      and split_part(object_name,'/',3)::int<t.image_count
      and object_name=c.owner_id::text||'/'||o.id::text||'/'||split_part(object_name,'/',3)
  );
$$;
