-- A repair lock takes precedence over an insufficient wallet in the public RPC.
create or replace function public.feed_cat(target_cat uuid) returns jsonb
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
  perform 1 from public.families where id=home for update;
  if exists(select 1 from public.repair_episodes
      where family_id=home and status in ('pending','active')) then
    raise exception 'Repair in progress' using errcode='22023';
  end if;
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
