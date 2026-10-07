-- Same approved 1:5 ratio, now exchange an explicitly entered quantity atomically.
do $$ declare previous text;
begin
 select pg_get_expr(conbin,conrelid) into previous from pg_constraint
   where conrelid='public.wallet_entries'::regclass and conname='wallet_entry_reward_shape';
 if previous is null then raise exception 'Wallet shape constraint missing'; end if;
 alter table public.wallet_entries drop constraint wallet_entry_reward_shape;
 execute 'alter table public.wallet_entries add constraint wallet_entry_reward_shape check ('||previous||
   ' or (kind=''exchange_eagle'' and eagle_delta<0 and gem_delta=0 and miao_delta::bigint=-eagle_delta::bigint*5 and business_day is null and operation_id is not null)'||
   ' or (kind=''exchange_gem'' and gem_delta<0 and eagle_delta=0 and miao_delta::bigint=-gem_delta::bigint*5 and business_day is null and operation_id is not null))';
end $$;

drop function public.exchange_special(uuid,text);
create function public.exchange_special(request_id uuid, source_currency text, quantity integer default 1) returns jsonb
language plpgsql security definer set search_path='' as $$
declare me uuid:=auth.uid(); wallet public.wallets; prior public.wallet_entries; credit bigint;
begin
 if me is null then raise exception 'Authentication required' using errcode='42501'; end if;
 if request_id is null or source_currency is null or source_currency not in ('eagle','gem') or quantity is null or quantity<1 or quantity>429496729 then
   raise exception 'Invalid exchange' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended(request_id::text,15));
 select * into wallet from public.wallets where owner_id=me for update;
 if not found then raise exception 'Wallet missing'; end if;
 select * into prior from public.wallet_entries where operation_id=request_id;
 if found then
   if prior.owner_id<>me or prior.kind<>'exchange_'||source_currency then raise exception 'Exchange identity mismatch' using errcode='42501'; end if;
   if prior.miao_delta::bigint<>quantity::bigint*5 then raise exception 'Exchange quantity mismatch' using errcode='22023'; end if;
   return public.task_state();
 end if;
 if (source_currency='eagle' and wallet.eagle_pounds<quantity) or (source_currency='gem' and wallet.gems<quantity) then
   raise exception 'Insufficient special currency' using errcode='22023'; end if;
 credit:=quantity::bigint*5;
 if wallet.miao_coins::bigint+credit>2147483647 then raise exception 'Wallet capacity exceeded' using errcode='22023'; end if;
 update public.wallets set miao_coins=miao_coins+credit,
   eagle_pounds=eagle_pounds-case when source_currency='eagle' then quantity else 0 end,
   gems=gems-case when source_currency='gem' then quantity else 0 end where owner_id=me;
 insert into public.wallet_entries(owner_id,kind,miao_delta,eagle_delta,gem_delta,operation_id) values
   (me,'exchange_'||source_currency,credit,case when source_currency='eagle' then -quantity else 0 end,
    case when source_currency='gem' then -quantity else 0 end,request_id);
 return public.task_state();
end $$;
revoke all on function public.exchange_special(uuid,text,integer) from public,anon;
grant execute on function public.exchange_special(uuid,text,integer) to authenticated;
