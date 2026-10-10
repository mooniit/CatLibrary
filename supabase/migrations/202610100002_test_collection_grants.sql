-- Explicit administrator-only test package. No startup grant or client mint RPC.
create table public.test_account_grants (
  request_id uuid primary key, owner_id uuid not null references public.wallets(owner_id),
  family_id uuid not null references public.families(id), receipt jsonb not null,
  created_at timestamptz not null default clock_timestamp()
);
create table public.test_photo_unlocks (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.wallets(owner_id),
  appearance text not null check(appearance in ('black_short','light_long')),
  destination text not null references public.travel_destinations(id),
  grant_id uuid not null references public.test_account_grants(request_id),
  unique(owner_id,appearance,destination)
);
alter table public.test_account_grants enable row level security;
alter table public.test_photo_unlocks enable row level security;
revoke all on public.test_account_grants,public.test_photo_unlocks from public,anon,authenticated,service_role;

do $$ declare previous text;
begin
  select pg_get_expr(conbin,conrelid) into strict previous from pg_constraint
    where conrelid='public.wallet_entries'::regclass and conname='wallet_entry_reward_shape';
  alter table public.wallet_entries drop constraint wallet_entry_reward_shape;
  execute 'alter table public.wallet_entries add constraint wallet_entry_reward_shape check ('||previous||
    ' or (kind=''test_grant'' and miao_delta=2000 and eagle_delta=12 and gem_delta=12 and business_day is null and operation_id is not null))';
end $$;

create function public.grant_test_collection(request_id uuid,target_owner uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare home uuid; prior public.test_account_grants; result jsonb; added_items integer; added_photos integer;
begin
  if request_id is null or target_owner is null then raise exception 'Invalid test grant' using errcode='22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended(request_id::text,101002));
  select * into prior from public.test_account_grants g where g.request_id=grant_test_collection.request_id;
  if found then
    if prior.owner_id<>target_owner then raise exception 'Test grant request belongs to another owner' using errcode='22023'; end if;
    return prior.receipt;
  end if;
  select family_id into home from public.family_members where user_id=target_owner;
  if home is null or not exists(select 1 from public.wallets where owner_id=target_owner) then
    raise exception 'Existing wallet and family required' using errcode='22023'; end if;
  perform 1 from public.families where id=home for update;
  if not exists(select 1 from public.family_members where user_id=target_owner and family_id=home) then
    raise exception 'Family membership changed' using errcode='42501'; end if;
  perform 1 from public.wallets where owner_id=target_owner for update;
  if (select count(*) from public.furniture_products p join public.travel_destinations d on d.souvenir_sku=p.sku
      where p.kind='souvenir' and not p.is_test)<>6 then
    raise exception 'Six registered souvenirs required' using errcode='22023'; end if;
  update public.wallets set miao_coins=miao_coins+2000,eagle_pounds=eagle_pounds+12,gems=gems+12 where owner_id=target_owner;
  insert into public.wallet_entries(owner_id,kind,miao_delta,eagle_delta,gem_delta,operation_id)
    values(target_owner,'test_grant',2000,12,12,request_id);
  insert into public.test_account_grants(request_id,owner_id,family_id,receipt) values(request_id,target_owner,home,'{}');
  insert into public.furniture_inventory(family_id,sku,purchased_by,source,source_id)
    select home,d.souvenir_sku,target_owner,'test_grant',request_id from public.travel_destinations d
    where not exists(select 1 from public.furniture_inventory i left join public.cats c on c.id=i.source_cat_id
      where i.family_id=home and i.sku=d.souvenir_sku and (i.purchased_by=target_owner or c.owner_id=target_owner));
  get diagnostics added_items=row_count;
  insert into public.test_photo_unlocks(owner_id,appearance,destination,grant_id)
    select target_owner,a.appearance,d.id,request_id from public.travel_destinations d
      cross join (values('black_short'),('light_long')) a(appearance) on conflict(owner_id,appearance,destination) do nothing;
  get diagnostics added_photos=row_count;
  result:=jsonb_build_object('status','granted','request_id',request_id,'owner_id',target_owner,'family_id',home,
    'miao_added',2000,'eagle_added',12,'gems_added',12,'souvenirs_added',added_items,'photos_added',added_photos,
    'wallet',(select jsonb_build_object('miao_coins',miao_coins,'eagle_pounds',eagle_pounds,'gems',gems)
      from public.wallets where owner_id=target_owner));
  update public.test_account_grants g set receipt=result where g.request_id=grant_test_collection.request_id;
  return result;
end $$;
revoke all on function public.grant_test_collection(uuid,uuid) from public,anon,authenticated,service_role;

-- Personal photo unlocks are separate from genuine cat visits and travel fee intervals.
alter function public.family_album() rename to family_album_before_test_unlocks;
revoke all on function public.family_album_before_test_unlocks() from public,anon,authenticated;
create function public.family_album() returns jsonb
language plpgsql security definer set search_path='' as $$
declare me uuid:=auth.uid(); base jsonb; unlocked jsonb;
begin
  if me is null then raise exception 'Authentication required' using errcode='42501'; end if;
  base:=public.family_album_before_test_unlocks();
  select coalesce(jsonb_agg(jsonb_build_object('id',u.id,'cat_id',null,
    'cat_name',case u.appearance when 'black_short' then '三花猫' else '蓝眸长毛猫' end,
    'appearance',u.appearance,'destination',d.id,'destination_label',d.label,
    'taken_at',g.created_at,'arranged_by',me,'arranger_label','测试解锁','source','test_grant',
    'inventory_id',(select i.id from public.furniture_inventory i left join public.cats c on c.id=i.source_cat_id
      where i.family_id=g.family_id and i.sku=d.souvenir_sku and (i.purchased_by=me or c.owner_id=me) order by i.created_at,i.id limit 1),
    'souvenir_label',p.label,'illustration_status','available') order by u.appearance,u.destination),'[]'::jsonb)
    into unlocked from public.test_photo_unlocks u join public.test_account_grants g on g.request_id=u.grant_id
    join public.travel_destinations d on d.id=u.destination join public.furniture_products p on p.sku=d.souvenir_sku
    where u.owner_id=me and g.family_id=(base->>'family_id')::uuid;
  return base||jsonb_build_object('photos',(base->'photos')||unlocked);
end $$;
revoke all on function public.family_album() from public,anon;
grant execute on function public.family_album() to authenticated;

-- The same family editor keeps shared usage; this field permits a personal inventory filter.
create or replace function public.furniture_state() returns jsonb
language plpgsql security definer set search_path='' as $$
declare home uuid; state jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  select family_id into home from public.family_members where user_id=auth.uid();
  perform public.return_family_trips(home);
  state:=public.furniture_state_base();
  return state||jsonb_build_object('inventory',coalesce((select jsonb_agg(to_jsonb(i)||jsonb_build_object(
    'source_cat_owner',c.owner_id,'source_cat_name',c.name,'source_destination',d.label,'source_date',t.ends_at) order by i.created_at,i.id)
    from public.furniture_inventory i left join public.cats c on c.id=i.source_cat_id
    left join public.cat_trips t on t.id=i.source_trip_id left join public.travel_destinations d on d.id=t.destination
    where i.family_id=home),'[]'::jsonb));
end $$;
