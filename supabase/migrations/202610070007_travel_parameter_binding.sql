-- Preserve request parameter binding after the internal function rename.
create or replace function public.start_cat_travel_transaction(request_id uuid,target_cat uuid,target_family uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare me uuid:=auth.uid(); home uuid; prior public.travel_requests; cat_row public.cats;
  moment timestamptz; destination_key text; reason text; result jsonb;
  request_payload jsonb:=jsonb_build_object('cat_id',target_cat,'family_id',target_family);
begin
  if me is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if request_id is null or target_cat is null or target_family is null then
    raise exception 'Invalid travel request' using errcode='22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended(request_id::text,29));
  select * into prior from public.travel_requests r where r.request_id=start_cat_travel_transaction.request_id;
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
