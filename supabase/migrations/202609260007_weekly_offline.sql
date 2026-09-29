-- A locally confirmed task may arrive after its week has ended.
drop trigger weekly_completion_current on public.weekly_task_completions;
drop function public.reject_expired_weekly_completion();
drop function public.weekly_offer_is_current(uuid,uuid);

create or replace function public.weekly_photo_writable(object_name text) returns boolean
language sql stable security definer set search_path='' as $$
  select exists (
    select 1 from public.weekly_task_completions c
      join public.weekly_task_offers o on o.id=c.offer_id and o.owner_id=c.owner_id
      join public.weekly_task_catalog t on t.id=o.task_id
    where c.owner_id=(select auth.uid()) and c.confirmed_at is null
      and o.id::text=split_part(object_name,'/',2)
      and split_part(object_name,'/',3) ~ '^[01]$'
      and split_part(object_name,'/',3)::int<t.image_count
      and object_name=c.owner_id::text||'/'||o.id::text||'/'||split_part(object_name,'/',3)
  );
$$;

drop function public.weekly_confirm(uuid);
create function public.weekly_confirm(target_offer uuid, claimed_at timestamptz) returns jsonb
language plpgsql security definer set search_path='' as $$
declare me uuid:=auth.uid(); offer_row public.weekly_task_offers;
  task_row public.weekly_task_catalog; current_row public.weekly_task_completions;
  paths text[]:='{}'; slot_index integer;
  week_end timestamptz;
begin
  if me is null then raise exception 'Authentication required' using errcode='42501'; end if;
  select * into offer_row from public.weekly_task_offers where id=target_offer for update;
  if not found or offer_row.owner_id<>me then
    raise exception 'Weekly task not assigned to this user' using errcode='42501';
  end if;
  select * into current_row from public.weekly_task_completions where offer_id=target_offer;
  if found and current_row.confirmed_at is not null then
    if current_row.confirmed_at<>claimed_at then
      raise exception 'Confirmed time is immutable' using errcode='22023';
    end if;
    return jsonb_build_object('tasks',public.weekly_my_tasks(),
      'wallet',public.task_state()->'wallet');
  end if;
  week_end := (offer_row.week_start+7)::timestamp at time zone 'Asia/Shanghai';
  if claimed_at is null or not isfinite(claimed_at)
    or claimed_at<offer_row.published_at or claimed_at>=week_end
    or claimed_at>clock_timestamp()+interval '5 minutes' then
    raise exception 'Confirmation time outside assigned week' using errcode='22023';
  end if;
  select * into task_row from public.weekly_task_catalog where id=offer_row.task_id;
  if task_row.evidence_kind='text' and
    (current_row.note is null or btrim(current_row.note)='') then
    raise exception 'Text evidence required' using errcode='22023';
  end if;
  if task_row.image_count>0 then
    if current_row.offer_id is null then
      raise exception 'Draft required before photo upload' using errcode='22023';
    end if;
    for slot_index in 0..task_row.image_count-1 loop
      paths := array_append(paths,me::text||'/'||target_offer::text||'/'||slot_index::text);
      if not exists(select 1 from storage.objects where bucket_id='weekly-photos'
        and name=paths[array_length(paths,1)]) then
        raise exception 'Required photo missing' using errcode='22023';
      end if;
    end loop;
  end if;
  insert into public.weekly_task_completions(offer_id,owner_id,photo_paths,confirmed_at)
    values(target_offer,me,paths,claimed_at)
    on conflict(offer_id) do update set photo_paths=excluded.photo_paths,
      confirmed_at=excluded.confirmed_at;
  perform 1 from public.wallets where owner_id=me for update;
  update public.wallets set gems=gems+6,eagle_pounds=eagle_pounds+6 where owner_id=me;
  insert into public.wallet_entries(owner_id,kind,miao_delta,eagle_delta,gem_delta,operation_id)
    values(me,'weekly',0,6,6,target_offer);
  return jsonb_build_object('tasks',public.weekly_my_tasks(),
    'wallet',public.task_state()->'wallet');
end;
$$;
revoke all on function public.weekly_confirm(uuid,timestamptz) from public,anon;
grant execute on function public.weekly_confirm(uuid,timestamptz) to authenticated;

create or replace function public.weekly_family_feed() returns jsonb
language sql stable security definer set search_path='' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'offer_id',c.offer_id,'owner_id',c.owner_id,'task_id',t.id,'prompt',t.prompt,
    'note',c.note,'photo_paths',to_jsonb(c.photo_paths),
    'confirmed_at',c.confirmed_at
  ) order by c.confirmed_at desc),'[]'::jsonb)
  from public.weekly_task_completions c
    join public.weekly_task_offers o on o.id=c.offer_id
    join public.weekly_task_catalog t on t.id=o.task_id
  where c.confirmed_at is not null and (c.owner_id=(select auth.uid()) or exists(
    select 1 from public.family_members a join public.family_members b
      on b.family_id=a.family_id
    where a.user_id=c.owner_id and b.user_id=(select auth.uid())));
$$;
