-- Prices, grants and production editor duration remain disabled until confirmed.
create table public.furniture_products (
  sku text primary key, label text not null, theme text not null,
  kind text not null, placement text not null check(placement in ('ground','window','art','rug','wall','floor')),
  geometry jsonb not null, price integer check(price>0),
  currency text check(currency in ('miao','eagle','gem')),
  purchase_limit integer check(purchase_limit between 1 and 64),
  active boolean not null default false, is_test boolean not null default false,
  check(not active or (price is not null and currency is not null and purchase_limit is not null))
);
create table public.room_policies (
  id text primary key check(id in ('production','test')),
  lease_seconds integer check(lease_seconds between 30 and 600),
  renewal_seconds integer check(renewal_seconds>0 and renewal_seconds<lease_seconds)
);
insert into public.room_policies(id) values('production'),('test');
create table public.room_test_families (
  family_id uuid primary key references public.families(id) on delete cascade
);
create table public.furniture_inventory (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  sku text not null references public.furniture_products(sku),
  purchased_by uuid references public.wallets(owner_id),
  source text not null check(source in ('purchase','initial','souvenir')),
  source_id uuid, created_at timestamptz not null default clock_timestamp()
);
create index furniture_family_inventory on public.furniture_inventory(family_id,sku);
create table public.furniture_requests (
  request_id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  family_id uuid references public.families(id) on delete cascade,
  operation text not null check(operation in ('purchase','save')),
  payload jsonb not null, result jsonb not null,
  created_at timestamptz not null default clock_timestamp()
);
create table public.room_layouts (
  family_id uuid primary key references public.families(id) on delete cascade,
  version bigint not null default 0,
  layout jsonb not null default '{"standard":"room-standard-v1","items":[]}',
  edited_by uuid references auth.users(id), updated_at timestamptz not null default clock_timestamp(),
  lock_user uuid references auth.users(id), lock_token uuid, lock_until timestamptz
);
alter table public.furniture_products enable row level security;
alter table public.furniture_inventory enable row level security;
alter table public.furniture_requests enable row level security;
alter table public.room_layouts enable row level security;
alter table public.room_policies enable row level security;
alter table public.room_test_families enable row level security;
revoke all on public.furniture_products,public.furniture_inventory,public.furniture_requests,
  public.room_layouts,public.room_policies,public.room_test_families from anon,authenticated;

-- Extend, rather than replace, the audited wallet shape from M4.
do $$ declare old_expression text;
begin
  select pg_get_expr(conbin,conrelid) into old_expression from pg_constraint
    where conrelid='public.wallet_entries'::regclass and conname='wallet_entry_reward_shape';
  if old_expression is null then raise exception 'Wallet shape constraint missing'; end if;
  alter table public.wallet_entries drop constraint wallet_entry_reward_shape;
  execute 'alter table public.wallet_entries add constraint wallet_entry_reward_shape check ('||
    old_expression||' or (kind=''furniture'' and business_day is null and operation_id is not null and
      ((miao_delta<0 and eagle_delta=0 and gem_delta=0) or
       (miao_delta=0 and eagle_delta<0 and gem_delta=0) or
       (miao_delta=0 and eagle_delta=0 and gem_delta<0))))';
end $$;

create function public.furniture_state() returns jsonb
language plpgsql security definer set search_path='' as $$
declare me uuid:=auth.uid(); home uuid; test_scope boolean; policy public.room_policies; room public.room_layouts;
begin
  if me is null then raise exception 'Authentication required' using errcode='42501'; end if;
  select family_id into home from public.family_members where user_id=me;
  test_scope:=exists(select 1 from public.room_test_families where family_id=home);
  select * into policy from public.room_policies where id=case when test_scope then 'test' else 'production' end;
  select * into room from public.room_layouts where family_id=home;
  return jsonb_build_object(
    'family_id',home,'test_scope',test_scope,'configured',policy.lease_seconds is not null,
    'lease_seconds',policy.lease_seconds,'renewal_seconds',policy.renewal_seconds,
    'server_time',clock_timestamp(),
    'products',coalesce((select jsonb_agg(to_jsonb(p) order by theme,kind,sku)
      from public.furniture_products p where not p.is_test or test_scope),'[]'::jsonb),
    'inventory',coalesce((select jsonb_agg(to_jsonb(i) order by created_at,id)
      from public.furniture_inventory i where family_id=home),'[]'::jsonb),
    'version',coalesce(room.version,0),'layout',coalesce(room.layout,'{"standard":"room-standard-v1","items":[]}'::jsonb),
    'edited_by',room.edited_by,'lock_user',room.lock_user,'lock_until',room.lock_until,
    'wallet',(select jsonb_build_object('owner_id',owner_id,'miao_coins',miao_coins,
      'eagle_pounds',eagle_pounds,'gems',gems) from public.wallets where owner_id=me));
end $$;

create function public.furniture_request(target_request uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare me uuid:=auth.uid(); prior public.furniture_requests;
begin
  if me is null then raise exception 'Authentication required' using errcode='42501'; end if;
  select * into prior from public.furniture_requests where request_id=target_request;
  if not found then return jsonb_build_object('status','not_found'); end if;
  if prior.user_id<>me then raise exception 'Request belongs to another user' using errcode='42501'; end if;
  return prior.result;
end $$;

create function public.purchase_furniture(request_id uuid, product_sku text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare me uuid:=auth.uid(); home uuid; prior public.furniture_requests;
  product public.furniture_products; wallet public.wallets; item uuid; reason text; result jsonb;
begin
  if me is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if request_id is null or product_sku is null then raise exception 'Invalid purchase' using errcode='22023'; end if;
  -- One request id across operations and users. Serializes even before a family exists.
  perform pg_advisory_xact_lock(hashtextextended(request_id::text,25));
  select * into prior from public.furniture_requests r where r.request_id=purchase_furniture.request_id;
  if found then
    if prior.user_id<>me then raise exception 'Request belongs to another user' using errcode='42501'; end if;
    if prior.operation<>'purchase' or prior.payload<>jsonb_build_object('sku',product_sku) then
      raise exception 'Request payload mismatch' using errcode='22023'; end if;
    return prior.result;
  end if;
  select family_id into home from public.family_members where user_id=me;
  if home is null then reason:='family_required';
  else
    -- Same family -> wallet lock order as daily fees and feeding.
    perform 1 from public.families where id=home for update;
    if not exists(select 1 from public.family_members where user_id=me and family_id=home) then
      raise exception 'Family membership changed' using errcode='42501'; end if;
    select * into product from public.furniture_products where sku=product_sku for share;
    if not found or not product.active or
      (product.is_test and not exists(select 1 from public.room_test_families where family_id=home)) then
      reason:='product_unavailable';
    elsif (select count(*) from public.furniture_inventory where family_id=home and sku=product_sku)>=product.purchase_limit then
      reason:='purchase_limit';
    else
      select * into wallet from public.wallets where owner_id=me for update;
      if not found then raise exception 'Wallet missing'; end if;
      if (case product.currency when 'miao' then wallet.miao_coins when 'eagle' then wallet.eagle_pounds else wallet.gems end)<product.price then
        reason:='insufficient_balance';
      else
        item:=gen_random_uuid();
        update public.wallets set
          miao_coins=miao_coins-case when product.currency='miao' then product.price else 0 end,
          eagle_pounds=eagle_pounds-case when product.currency='eagle' then product.price else 0 end,
          gems=gems-case when product.currency='gem' then product.price else 0 end where owner_id=me;
        insert into public.wallet_entries(owner_id,kind,miao_delta,eagle_delta,gem_delta,operation_id)
          values(me,'furniture',case when product.currency='miao' then -product.price else 0 end,
            case when product.currency='eagle' then -product.price else 0 end,
            case when product.currency='gem' then -product.price else 0 end,request_id);
        insert into public.furniture_inventory(id,family_id,sku,purchased_by,source,source_id)
          values(item,home,product_sku,me,'purchase',request_id);
      end if;
    end if;
  end if;
  result:=jsonb_build_object('status',case when reason is null then 'purchased' else 'rejected' end,
    'reason',reason,'request_id',request_id,'family_id',home,'sku',product_sku,
    'instance_id',item,'payer_id',me,'price',case when reason is null then product.price end,
    'currency',case when reason is null then product.currency end);
  insert into public.furniture_requests values(request_id,me,home,'purchase',jsonb_build_object('sku',product_sku),result,clock_timestamp());
  return result;
end $$;
revoke all on function public.furniture_state(),public.furniture_request(uuid),public.purchase_furniture(uuid,text) from public,anon;
grant execute on function public.furniture_state(),public.furniture_request(uuid),public.purchase_furniture(uuid,text) to authenticated;
