-- M3 T15: one-way, idempotent special-currency exchange.
alter table public.wallet_entries add column operation_id uuid unique;
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
    and business_day is null and operation_id is not null)
);

create function public.exchange_special(request_id uuid, source_currency text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare me uuid:=auth.uid(); wallet public.wallets; prior public.wallet_entries;
begin
  if me is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if request_id is null or source_currency not in ('eagle','gem') then
    raise exception 'Invalid exchange' using errcode='22023';
  end if;
  select * into wallet from public.wallets where owner_id=me for update;
  if not found then raise exception 'Wallet missing'; end if;
  select * into prior from public.wallet_entries where operation_id=request_id;
  if found then
    if prior.owner_id<>me or prior.kind<>'exchange_'||source_currency then
      raise exception 'Exchange identity mismatch' using errcode='42501';
    end if;
    return public.task_state();
  end if;
  if (source_currency='eagle' and wallet.eagle_pounds<1)
    or (source_currency='gem' and wallet.gems<1) then
    raise exception 'Insufficient special currency' using errcode='22023';
  end if;
  if source_currency='eagle' then
    update public.wallets set eagle_pounds=eagle_pounds-1,miao_coins=miao_coins+5 where owner_id=me;
    insert into public.wallet_entries(owner_id,kind,miao_delta,eagle_delta,operation_id)
      values(me,'exchange_eagle',5,-1,request_id);
  else
    update public.wallets set gems=gems-1,miao_coins=miao_coins+5 where owner_id=me;
    insert into public.wallet_entries(owner_id,kind,miao_delta,gem_delta,operation_id)
      values(me,'exchange_gem',5,-1,request_id);
  end if;
  return public.task_state();
end;
$$;
revoke all on function public.exchange_special(uuid,text) from public,anon;
grant execute on function public.exchange_special(uuid,text) to authenticated;
