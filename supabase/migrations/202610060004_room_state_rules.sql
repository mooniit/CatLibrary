-- Every caller receives the server's current placement rules, including after save.
create or replace function public.furniture_state() returns jsonb
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
    'category_limits',(select jsonb_object_agg(kind,max_placed) from public.room_category_limits),
    'slots',(select jsonb_object_agg(id,placement) from public.room_slots),
    'products',coalesce((select jsonb_agg(to_jsonb(p) order by theme,kind,sku)
      from public.furniture_products p where not p.is_test or test_scope),'[]'::jsonb),
    'inventory',coalesce((select jsonb_agg(to_jsonb(i) order by created_at,id)
      from public.furniture_inventory i where family_id=home),'[]'::jsonb),
    'version',coalesce(room.version,0),'layout',coalesce(room.layout,'{"standard":"room-standard-v1","items":[]}'::jsonb),
    'edited_by',room.edited_by,'lock_user',room.lock_user,'lock_until',room.lock_until,
    'wallet',(select jsonb_build_object('owner_id',owner_id,'miao_coins',miao_coins,
      'eagle_pounds',eagle_pounds,'gems',gems) from public.wallets where owner_id=me));
end $$;
