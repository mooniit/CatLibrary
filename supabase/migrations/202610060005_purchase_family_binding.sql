-- Bind persisted native purchases to the household originally selected.
drop function public.purchase_furniture(uuid,text);
create function public.purchase_furniture(request_id uuid, product_sku text, target_family uuid default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare me uuid:=auth.uid(); home uuid; prior public.furniture_requests;
  product public.furniture_products; wallet public.wallets; item uuid; reason text; result jsonb; request_payload jsonb;
begin
  if me is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if request_id is null or product_sku is null then raise exception 'Invalid purchase' using errcode='22023'; end if;
  request_payload:=jsonb_build_object('sku',product_sku)||case when target_family is null then '{}'::jsonb
    else jsonb_build_object('target_family',target_family) end;
  perform pg_advisory_xact_lock(hashtextextended(request_id::text,25));
  select * into prior from public.furniture_requests r where r.request_id=purchase_furniture.request_id;
  if found then
    if prior.user_id<>me then raise exception 'Request belongs to another user' using errcode='42501'; end if;
    if prior.operation<>'purchase' or prior.payload<>request_payload then
      raise exception 'Request payload mismatch' using errcode='22023'; end if;
    return prior.result;
  end if;
  select family_id into home from public.family_members where user_id=me;
  if home is null then reason:='family_required';
  elsif target_family is not null and target_family<>home then reason:='family_changed';
  else
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
    'reason',reason,'request_id',request_id,'family_id',coalesce(target_family,home),'sku',product_sku,
    'instance_id',item,'payer_id',me,'price',case when reason is null then product.price end,
    'currency',case when reason is null then product.currency end);
  insert into public.furniture_requests values(request_id,me,home,'purchase',request_payload,result,clock_timestamp());
  return result;
end $$;
revoke all on function public.purchase_furniture(uuid,text,uuid) from public,anon;
grant execute on function public.purchase_furniture(uuid,text,uuid) to authenticated;
alter table public.room_policies add constraint room_policy_pair check
  ((lease_seconds is null and renewal_seconds is null) or (lease_seconds is not null and renewal_seconds is not null));
