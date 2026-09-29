-- T17: one paid feeding per cat and Beijing calendar day.
create table public.cat_feedings (
  cat_id uuid not null references public.cats(id),
  business_day date not null,
  payer_id uuid not null references public.wallets(owner_id),
  paid_at timestamptz not null default clock_timestamp(),
  primary key(cat_id,business_day)
);
create index cat_feedings_payer on public.cat_feedings(payer_id,business_day desc);
alter table public.cat_feedings enable row level security;
revoke all on public.cat_feedings from anon,authenticated;

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
    and business_day is null and operation_id is not null) or
  (kind='feeding' and miao_delta=-15 and eagle_delta=0 and gem_delta=0
    and business_day is not null and operation_id is null)
);

create or replace function public.cats_state() returns jsonb
language plpgsql security definer set search_path='' as $$
declare me uuid:=auth.uid(); home uuid;
  today date:=(clock_timestamp() at time zone 'Asia/Shanghai')::date;
begin
  if me is null then raise exception 'Authentication required' using errcode='42501'; end if;
  select family_id into home from public.family_members where user_id=me;
  return jsonb_build_object(
    'family_id',home,
    'remaining',2-(select count(*) from public.cats where owner_id=me),
    'wallet',(select jsonb_build_object('owner_id',owner_id,'miao_coins',miao_coins,
      'eagle_pounds',eagle_pounds,'gems',gems) from public.wallets where owner_id=me),
    'cats',coalesce((select jsonb_agg(jsonb_build_object(
      'id',c.id,'name',c.name,'appearance',c.appearance,'owner_id',c.owner_id,
      'is_mine',c.owner_id=me,'fed_today',f.cat_id is not null,
      'fed_by',f.payer_id) order by c.adopted_at,c.id)
      from public.cats c left join public.cat_feedings f
        on f.cat_id=c.id and f.business_day=today
      where c.family_id=home),'[]'::jsonb)
  );
end; $$;

create function public.feed_cat(target_cat uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare me uuid:=auth.uid(); cat_row public.cats; home uuid;
  today date:=(clock_timestamp() at time zone 'Asia/Shanghai')::date;
  balance integer;
begin
  if me is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if target_cat is null then raise exception 'Cat required' using errcode='22023'; end if;
  select * into cat_row from public.cats where id=target_cat;
  if not found then raise exception 'Cat not found' using errcode='22023'; end if;
  select family_id into home from public.family_members where user_id=me;
  if home is distinct from cat_row.family_id then
    raise exception 'Cat is outside your family' using errcode='42501';
  end if;
  -- Family lock serializes both members and later daily settlement before wallets.
  perform 1 from public.families where id=home for update;
  if exists(select 1 from public.cat_feedings
      where cat_id=target_cat and business_day=today) then
    return public.cats_state() || jsonb_build_object('outcome','already_fed');
  end if;
  select miao_coins into balance from public.wallets where owner_id=me for update;
  if not found then raise exception 'Wallet missing'; end if;
  if balance<15 then raise exception 'Insufficient miao coins' using errcode='22023'; end if;
  insert into public.cat_feedings(cat_id,business_day,payer_id)
    values(target_cat,today,me);
  update public.wallets set miao_coins=miao_coins-15 where owner_id=me;
  insert into public.wallet_entries(owner_id,kind,miao_delta,business_day)
    values(me,'feeding',-15,today);
  return public.cats_state() || jsonb_build_object('outcome','fed');
end; $$;
revoke all on function public.feed_cat(uuid) from public,anon;
grant execute on function public.feed_cat(uuid) to authenticated;
