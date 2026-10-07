-- T29: immutable clock intervals and durable receipts; no client prices or destinations.
create table public.travel_destinations (
  id text primary key, label text not null, souvenir_sku text not null unique
);
insert into public.travel_destinations values
 ('palace','故宫','souvenir-palace'),('louvre','卢浮宫','souvenir-louvre'),
 ('fuji','富士山','souvenir-fuji'),('pyramid','金字塔','souvenir-pyramid'),
 ('eiffel','埃菲尔铁塔','souvenir-eiffel'),('liberty','自由女神像','souvenir-liberty');
create table public.cat_trips (
  id uuid primary key, family_id uuid not null references public.families(id),
  cat_id uuid not null references public.cats(id), arranged_by uuid not null references public.wallets(owner_id),
  destination text not null references public.travel_destinations(id),
  started_at timestamptz not null, ends_at timestamptz not null,
  returned_at timestamptz, check(ends_at=started_at+interval '24 hours')
);
create unique index one_unreturned_trip on public.cat_trips(cat_id) where returned_at is null;
create index trips_due on public.cat_trips(ends_at) where returned_at is null;
create table public.cat_travel_visits (
  id uuid primary key default gen_random_uuid(), cat_id uuid not null references public.cats(id),
  destination text not null references public.travel_destinations(id),
  trip_id uuid not null unique references public.cat_trips(id),
  inventory_id uuid not null unique references public.furniture_inventory(id),
  unique(cat_id,destination)
);
create table public.travel_requests (
  request_id uuid primary key, user_id uuid not null references auth.users(id),
  family_id uuid references public.families(id), payload jsonb not null, result jsonb not null,
  created_at timestamptz not null default clock_timestamp()
);
alter table public.travel_destinations enable row level security;
alter table public.cat_trips enable row level security;
alter table public.cat_travel_visits enable row level security;
alter table public.travel_requests enable row level security;
revoke all on public.travel_destinations,public.cat_trips,public.cat_travel_visits,public.travel_requests from anon,authenticated;
do $$ declare old_expression text;
begin
  select pg_get_expr(conbin,conrelid) into old_expression from pg_constraint
    where conrelid='public.wallet_entries'::regclass and conname='wallet_entry_reward_shape';
  if old_expression is null then raise exception 'Wallet shape constraint missing'; end if;
  alter table public.wallet_entries drop constraint wallet_entry_reward_shape;
  execute 'alter table public.wallet_entries add constraint wallet_entry_reward_shape check ('||old_expression||
    ' or (kind=''travel'' and miao_delta=0 and eagle_delta=0 and gem_delta=-60 and business_day is null and operation_id is not null))';
end $$;
create function public.travel_request(target_request uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare me uuid:=auth.uid(); prior public.travel_requests;
begin
  if me is null then raise exception 'Authentication required' using errcode='42501'; end if;
  select * into prior from public.travel_requests where request_id=target_request;
  if not found then return jsonb_build_object('status','not_found'); end if;
  if prior.user_id<>me then raise exception 'Request belongs to another user' using errcode='42501'; end if;
  return prior.result;
end $$;
create function public.start_cat_travel(request_id uuid,target_cat uuid,target_family uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare me uuid:=auth.uid(); home uuid; prior public.travel_requests; cat_row public.cats;
  moment timestamptz; destination_key text; reason text; result jsonb;
  request_payload jsonb:=jsonb_build_object('cat_id',target_cat,'family_id',target_family);
begin
  if me is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if request_id is null or target_cat is null or target_family is null then
    raise exception 'Invalid travel request' using errcode='22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended(request_id::text,29));
  select * into prior from public.travel_requests r where r.request_id=start_cat_travel.request_id;
  if found then
    if prior.user_id<>me then raise exception 'Request belongs to another user' using errcode='42501'; end if;
    if prior.payload<>request_payload then raise exception 'Request payload mismatch' using errcode='22023'; end if;
    return prior.result;
  end if;
  select family_id into home from public.family_members where user_id=me;
  if home is null then reason:='family_required';
  elsif home<>target_family then reason:='family_changed';
  else
    perform 1 from public.families where id=home for update;
    if not exists(select 1 from public.family_members where user_id=me and family_id=home) then
      raise exception 'Family membership changed' using errcode='42501'; end if;
    select * into cat_row from public.cats where id=target_cat and family_id=home;
    if not found then reason:='cat_unavailable';
    elsif exists(select 1 from public.repair_episodes where family_id=home and status in ('pending','active')) then reason:='repair_in_progress';
    elsif exists(select 1 from public.cat_trips where cat_id=target_cat and returned_at is null) then reason:='already_traveling';
    else
      perform 1 from public.wallets where owner_id=me for update;
      if not found then raise exception 'Wallet missing'; end if;
      if (select gems from public.wallets where owner_id=me)<60 then reason:='insufficient_gems';
      else
        select d.id into destination_key from public.travel_destinations d
          where not exists(select 1 from public.cat_travel_visits v where v.cat_id=target_cat and v.destination=d.id)
          order by random() limit 1;
        if destination_key is null then select id into destination_key from public.travel_destinations order by random() limit 1; end if;
        moment:=clock_timestamp();
        insert into public.cat_trips values(request_id,home,target_cat,me,destination_key,moment,moment+interval '24 hours',null);
        update public.wallets set gems=gems-60 where owner_id=me;
        insert into public.wallet_entries(owner_id,kind,miao_delta,eagle_delta,gem_delta,operation_id)
          values(me,'travel',0,0,-60,request_id);
      end if;
    end if;
  end if;
  result:=jsonb_build_object('status',case when reason is null then 'started' else 'rejected' end,
    'request_id',request_id,'family_id',home,'cat_id',target_cat,'reason',reason,
    'trip_id',case when reason is null then request_id end,'started_at',moment,
    'ends_at',moment+interval '24 hours','payer_id',me,'price',case when reason is null then 60 end);
  insert into public.travel_requests(request_id,user_id,family_id,payload,result)
    values(request_id,me,home,request_payload,result);
  return result;
end $$;
create function public.travel_state() returns jsonb
language plpgsql security definer set search_path='' as $$
declare me uuid:=auth.uid(); home uuid;
begin
  if me is null then raise exception 'Authentication required' using errcode='42501'; end if;
  select family_id into home from public.family_members where user_id=me;
  return jsonb_build_object('family_id',home,'server_time',clock_timestamp(),
    'repairing',exists(select 1 from public.repair_episodes where family_id=home and status in ('pending','active')),
    'destinations',(select jsonb_agg(jsonb_build_object('id',id,'label',label) order by id) from public.travel_destinations),
    'cats',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'appearance',c.appearance,
      'trip_id',t.id,'ends_at',t.ends_at,'visited',(select count(*) from public.cat_travel_visits v where v.cat_id=c.id))
      order by c.adopted_at,c.id) from public.cats c left join public.cat_trips t on t.cat_id=c.id and t.returned_at is null
      where c.family_id=home),'[]'::jsonb),
    'wallet',public.bootstrap_identity());
end $$;
revoke all on function public.travel_request(uuid),public.start_cat_travel(uuid,uuid,uuid),public.travel_state() from public,anon;
grant execute on function public.travel_request(uuid),public.start_cat_travel(uuid,uuid,uuid),public.travel_state() to authenticated;
