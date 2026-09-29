-- T16: first-release catalog, evidence, personal weekly offers and atomic rewards.
create table public.weekly_task_catalog (
  id text primary key,
  prompt text not null,
  evidence_kind text not null check(evidence_kind in ('self','text','photo','screenshot')),
  image_count smallint not null check(image_count between 0 and 2),
  check((evidence_kind in ('photo','screenshot')) = (image_count > 0))
);
insert into public.weekly_task_catalog(id,prompt,evidence_kind,image_count) values
  ('1','看一场辩论赛，说出一个让你改变想法的观点','text',0),
  ('2','看一集从未看过的纪录片，记下最意外的画面','text',0),
  ('3','看一部一直想看却搁置的电影','self',0),
  ('7','出门拍一朵你觉得最漂亮的花','photo',1),
  ('9','找到一处以前没注意过的街头装饰并拍照','photo',1),
  ('12','在一天中的两个时刻拍同一片天空','photo',2),
  ('13','折一个纸作品并拍照','photo',1),
  ('14','随手画一张五分钟小画，不要求画得好','self',0),
  ('18','写一段不超过 100 字的小故事','text',0),
  ('22','重新布置家中的一个小角落','self',0),
  ('24','为自己安排一次不看手机的慢早餐或下午茶','self',0),
  ('50','听一期以讲故事为主的播客','self',0),
  ('L1','学三句法语，并上传记录三句的截图','screenshot',1),
  ('L2','学三句韩语，并上传记录三句的截图','screenshot',1),
  ('L3','学三句西班牙语，并上传记录三句的截图','screenshot',1);

-- Offers are durable draw history. Batch membership can later represent either
-- shared family picks or personal picks without changing completion ownership.
create table public.weekly_task_offers (
  id uuid primary key,
  owner_id uuid not null references public.wallets(owner_id),
  batch_id uuid not null,
  week_start date not null,
  cycle_no integer not null check(cycle_no>=1),
  slot smallint not null check(slot in (0,1)),
  task_id text not null references public.weekly_task_catalog(id),
  published_at timestamptz not null default now(),
  unique(owner_id,week_start,slot),
  unique(owner_id,week_start,task_id)
);
create index weekly_offer_owner on public.weekly_task_offers(owner_id,published_at desc);
create table public.weekly_task_completions (
  offer_id uuid primary key references public.weekly_task_offers(id),
  owner_id uuid not null references public.wallets(owner_id),
  note text,
  photo_paths text[] not null default '{}',
  confirmed_at timestamptz,
  check(note is null or char_length(note)<=100)
);
create index weekly_completion_owner on public.weekly_task_completions(owner_id);
alter table public.weekly_task_catalog enable row level security;
alter table public.weekly_task_offers enable row level security;
alter table public.weekly_task_completions enable row level security;
revoke all on public.weekly_task_catalog,public.weekly_task_offers,
  public.weekly_task_completions from anon,authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
  values('weekly-photos','weekly-photos',false,5242880,array['image/jpeg','image/png'])
  on conflict(id) do nothing;

create function public.weekly_photo_writable(object_name text) returns boolean
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
revoke all on function public.weekly_photo_writable(text) from public,anon;
grant execute on function public.weekly_photo_writable(text) to authenticated;

create function public.weekly_photo_visible(object_name text) returns boolean
language sql stable security definer set search_path='' as $$
  select (select auth.uid())::text=split_part(object_name,'/',1) or exists (
    select 1 from public.weekly_task_completions c
      join public.family_members a on a.user_id=c.owner_id
      join public.family_members b on b.family_id=a.family_id
    where c.confirmed_at is not null and object_name=any(c.photo_paths)
      and b.user_id=(select auth.uid())
  );
$$;
revoke all on function public.weekly_photo_visible(text) from public,anon;
grant execute on function public.weekly_photo_visible(text) to authenticated;
create policy weekly_photo_read on storage.objects for select to authenticated
  using(bucket_id='weekly-photos' and public.weekly_photo_visible(name));
create policy weekly_photo_insert on storage.objects for insert to authenticated
  with check(bucket_id='weekly-photos' and public.weekly_photo_writable(name));
create policy weekly_photo_update on storage.objects for update to authenticated
  using(bucket_id='weekly-photos' and public.weekly_photo_writable(name))
  with check(bucket_id='weekly-photos' and public.weekly_photo_writable(name));
create policy weekly_photo_delete on storage.objects for delete to authenticated
  using(bucket_id='weekly-photos' and public.weekly_photo_writable(name));

create function public.weekly_my_tasks() returns jsonb
language sql stable security definer set search_path='' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'offer_id',o.id,'batch_id',o.batch_id,'week_start',o.week_start,
    'task_id',t.id,'prompt',t.prompt,
    'evidence_kind',t.evidence_kind,'image_count',t.image_count,
    'published_at',o.published_at,'confirmed_at',c.confirmed_at,
    'note',c.note,'photo_paths',coalesce(to_jsonb(c.photo_paths),'[]'::jsonb),
    'reward_status',case when c.confirmed_at is null then null else 'credited' end
  ) order by o.published_at desc,o.slot),'[]'::jsonb)
  from public.weekly_task_offers o
    join public.weekly_task_catalog t on t.id=o.task_id
    left join public.weekly_task_completions c on c.offer_id=o.id
  where o.owner_id=(select auth.uid())
    and o.week_start=((clock_timestamp() at time zone 'Asia/Shanghai')::date
      - (extract(isodow from clock_timestamp() at time zone 'Asia/Shanghai')::int-1));
$$;
revoke all on function public.weekly_my_tasks() from public,anon;
grant execute on function public.weekly_my_tasks() to authenticated;

create function public.weekly_save_draft(target_offer uuid, draft_note text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare me uuid:=auth.uid(); offer_row public.weekly_task_offers; task_row public.weekly_task_catalog;
begin
  if me is null then raise exception 'Authentication required' using errcode='42501'; end if;
  select * into offer_row from public.weekly_task_offers where id=target_offer for update;
  if not found or offer_row.owner_id<>me then
    raise exception 'Weekly task not assigned to this user' using errcode='42501';
  end if;
  select * into task_row from public.weekly_task_catalog where id=offer_row.task_id;
  if task_row.evidence_kind='text' then
    draft_note := nullif(btrim(draft_note),'');
    if draft_note is not null and char_length(draft_note)>100 then
      raise exception 'Text is longer than 100 characters' using errcode='22023';
    end if;
  elsif draft_note is not null then
    raise exception 'This task does not require text' using errcode='22023';
  end if;
  if exists(select 1 from public.weekly_task_completions
    where offer_id=target_offer and confirmed_at is not null) then
    raise exception 'Confirmed completion is immutable' using errcode='22023';
  end if;
  insert into public.weekly_task_completions(offer_id,owner_id,note)
    values(target_offer,me,draft_note)
    on conflict(offer_id) do update set note=excluded.note;
  return public.weekly_my_tasks();
end;
$$;
revoke all on function public.weekly_save_draft(uuid,text) from public,anon;
grant execute on function public.weekly_save_draft(uuid,text) to authenticated;

create function public.weekly_confirm(target_offer uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare me uuid:=auth.uid(); offer_row public.weekly_task_offers;
  task_row public.weekly_task_catalog; current_row public.weekly_task_completions;
  paths text[]:='{}'; slot_index integer;
begin
  if me is null then raise exception 'Authentication required' using errcode='42501'; end if;
  select * into offer_row from public.weekly_task_offers where id=target_offer for update;
  if not found or offer_row.owner_id<>me then
    raise exception 'Weekly task not assigned to this user' using errcode='42501';
  end if;
  select * into task_row from public.weekly_task_catalog where id=offer_row.task_id;
  select * into current_row from public.weekly_task_completions where offer_id=target_offer;
  if found and current_row.confirmed_at is not null then
    return jsonb_build_object('tasks',public.weekly_my_tasks(),
      'wallet',public.task_state()->'wallet');
  end if;
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
    values(target_offer,me,paths,clock_timestamp())
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
revoke all on function public.weekly_confirm(uuid) from public,anon;
grant execute on function public.weekly_confirm(uuid) to authenticated;

alter table public.wallet_entries drop constraint wallet_entry_reward_shape;
alter table public.wallet_entries add constraint wallet_entry_reward_shape check (
  (kind='initial' and miao_delta=30 and eagle_delta=0 and gem_delta=0
    and business_day is null and operation_id is null) or
  (kind='study' and miao_delta>0 and miao_delta<=120 and eagle_delta=0 and gem_delta=0
    and business_day is not null and operation_id is null) or
  (kind='task_language' and miao_delta=0 and eagle_delta between 1 and 12 and gem_delta=0
    and business_day is not null and operation_id is null) or
  (kind='task_exercise' and miao_delta=0 and eagle_delta=0 and gem_delta between 1 and 12
    and business_day is not null and operation_id is null) or
  (kind='exchange_eagle' and miao_delta=5 and eagle_delta=-1 and gem_delta=0
    and business_day is null and operation_id is not null) or
  (kind='exchange_gem' and miao_delta=5 and eagle_delta=0 and gem_delta=-1
    and business_day is null and operation_id is not null) or
  (kind='weekly' and miao_delta=0 and eagle_delta=6 and gem_delta=6
    and business_day is null and operation_id is not null)
);

create function public.weekly_family_feed() returns jsonb
language sql stable security definer set search_path='' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'owner_id',c.owner_id,'task_id',t.id,'prompt',t.prompt,'note',c.note,
    'photo_paths',to_jsonb(c.photo_paths),'confirmed_at',c.confirmed_at
  ) order by c.confirmed_at desc),'[]'::jsonb)
  from public.weekly_task_completions c
    join public.weekly_task_offers o on o.id=c.offer_id
    join public.weekly_task_catalog t on t.id=o.task_id
  where c.confirmed_at is not null and (c.owner_id=(select auth.uid()) or exists(
    select 1 from public.family_members a join public.family_members b
      on b.family_id=a.family_id
    where a.user_id=c.owner_id and b.user_id=(select auth.uid())));
$$;
revoke all on function public.weekly_family_feed() from public,anon;
grant execute on function public.weekly_family_feed() to authenticated;
