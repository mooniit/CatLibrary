create table public.room_category_limits (kind text primary key, max_placed integer not null check(max_placed>0));
insert into public.room_category_limits values ('desk',1),('bed',1),('tree',1);
create table public.room_slots (id text primary key, placement text not null);
insert into public.room_slots values ('window-left','window'),('window-right','window'),
 ('art-left-back','art'),('art-left-front','art'),('art-right-back','art'),('art-right-front','art'),
 ('rug','rug'),('wall','wall'),('floor','floor');
alter table public.room_slots enable row level security;
alter table public.room_category_limits enable row level security;
revoke all on public.room_slots,public.room_category_limits from anon,authenticated;

create function public.validate_room_layout(home uuid, proposed jsonb) returns text
language plpgsql security definer set search_path='' as $$
declare item jsonb; instance public.furniture_inventory; product public.furniture_products;
  seen_ids text[]:='{}'; occupied text[]:='{}'; mounts text[]:='{}';
  counts jsonb:='{}'; n integer; cap integer; cell jsonb; x integer; y integer; key text; facing text; slot text;
begin
  if proposed->>'standard' is distinct from 'room-standard-v1' or
    jsonb_typeof(proposed->'items') is distinct from 'array' then return 'invalid_layout'; end if;
  if jsonb_array_length(proposed->'items')>74 then return 'invalid_layout'; end if;
  for item in select value from jsonb_array_elements(proposed->'items') loop
    if jsonb_typeof(item)<>'object' or item->>'instance_id' is null then return 'invalid_layout'; end if;
    key:=item->>'instance_id';
    if key=any(seen_ids) then return 'duplicate_instance'; end if;
    seen_ids:=array_append(seen_ids,key);
    select * into instance from public.furniture_inventory where id=key::uuid and family_id=home;
    if not found then return 'inventory_missing'; end if;
    select * into product from public.furniture_products where sku=instance.sku;
    facing:=item->>'facing'; slot:=item->>'slot';
    if facing is null or facing not in ('x','y') then return 'invalid_facing'; end if;
    if jsonb_typeof(item->'gx') is distinct from 'number' or jsonb_typeof(item->'gy') is distinct from 'number' or
      (item->>'gx')!~'^-?[0-9]+$' or (item->>'gy')!~'^-?[0-9]+$' then return 'invalid_anchor'; end if;
    if product.placement='ground' then
      if slot is not null then return 'invalid_slot'; end if;
      n:=coalesce((counts->>product.kind)::int,0)+1;
      counts:=jsonb_set(counts,array[product.kind],to_jsonb(n));
      select max_placed into cap from public.room_category_limits where kind=product.kind;
      if cap is not null and n>cap then return 'category_limit'; end if;
      for cell in select value from jsonb_array_elements(product.geometry->facing->'cells') loop
        x:=(cell->>0)::int+(item->>'gx')::int; y:=(cell->>1)::int+(item->>'gy')::int;
        if x<0 or y<0 or x>=8 or y>=8 then return 'out_of_bounds'; end if;
        key:=x||','||y;
        if key=any(occupied) then return 'cell_conflict'; end if;
        occupied:=array_append(occupied,key);
      end loop;
    else
      if not exists(select 1 from public.room_slots where id=slot and placement=product.placement) then return 'invalid_slot'; end if;
      if slot=any(mounts) then return 'slot_conflict'; end if;
      mounts:=array_append(mounts,slot);
      if (item->>'gx')::int<>0 or (item->>'gy')::int<>0 or facing<>'x' then return 'fixed_position'; end if;
      if product.placement='art' and (item->>'artwork' is null or item->>'artwork' not in ('starry','mona','scream','pearl','sunflowers')) then return 'invalid_artwork'; end if;
    end if;
  end loop;
  return null;
exception when invalid_text_representation or numeric_value_out_of_range then return 'invalid_layout';
end $$;
revoke all on function public.validate_room_layout(uuid,jsonb) from public,anon,authenticated;

create function public.room_editor(action text, editor_token uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare me uuid:=auth.uid(); home uuid; room public.room_layouts; policy public.room_policies; moment timestamptz;
begin
  if me is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if editor_token is null or action is null or action not in ('acquire','renew','release') then
    raise exception 'Invalid editor request' using errcode='22023'; end if;
  select family_id into home from public.family_members where user_id=me;
  if home is null then return jsonb_build_object('status','rejected','reason','family_required'); end if;
  perform 1 from public.families where id=home for update;
  if not exists(select 1 from public.family_members where user_id=me and family_id=home) then
    raise exception 'Family membership changed' using errcode='42501'; end if;
  select * into policy from public.room_policies where id=case when
    exists(select 1 from public.room_test_families where family_id=home) then 'test' else 'production' end;
  if policy.lease_seconds is null then return jsonb_build_object('status','rejected','reason','policy_unconfirmed'); end if;
  insert into public.room_layouts(family_id) values(home) on conflict do nothing;
  select * into room from public.room_layouts where family_id=home for update;
  moment:=clock_timestamp();
  if action='release' then
    if room.lock_user=me and room.lock_token=editor_token then
      update public.room_layouts set lock_user=null,lock_token=null,lock_until=null where family_id=home;
    end if;
    return jsonb_build_object('status','released');
  end if;
  if action='renew' and (room.lock_user is distinct from me or room.lock_token is distinct from editor_token or
    room.lock_until is null or room.lock_until<=moment) then
    return jsonb_build_object('status','rejected','reason','lease_expired');
  end if;
  if action='acquire' and room.lock_until>moment and
    (room.lock_user is distinct from me or room.lock_token is distinct from editor_token) then
    return jsonb_build_object('status','rejected','reason','editor_busy','lock_until',room.lock_until);
  end if;
  update public.room_layouts set lock_user=me,lock_token=editor_token,
    lock_until=moment+make_interval(secs=>policy.lease_seconds) where family_id=home;
  return public.furniture_state()||jsonb_build_object('status','acquired','editor_token',editor_token,
    'category_limits',(select jsonb_object_agg(kind,max_placed) from public.room_category_limits),
    'slots',(select jsonb_object_agg(id,placement) from public.room_slots));
end $$;

create function public.save_room_layout(request_id uuid,editor_token uuid,expected_version bigint,proposed jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare me uuid:=auth.uid(); home uuid; room public.room_layouts; prior public.furniture_requests;
  request_payload jsonb; reason text; result jsonb;
begin
  if me is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if request_id is null or editor_token is null or expected_version is null or proposed is null then
    raise exception 'Invalid save request' using errcode='22023'; end if;
  request_payload:=jsonb_build_object('editor_token',editor_token,'expected_version',expected_version,'proposed',proposed);
  perform pg_advisory_xact_lock(hashtextextended(request_id::text,25));
  select * into prior from public.furniture_requests r where r.request_id=save_room_layout.request_id;
  if found then
    if prior.user_id<>me then raise exception 'Request belongs to another user' using errcode='42501'; end if;
    if prior.operation<>'save' or prior.payload<>request_payload then
      raise exception 'Request payload mismatch' using errcode='22023'; end if;
    return prior.result;
  end if;
  select family_id into home from public.family_members where user_id=me;
  if home is null then reason:='family_required';
  else
    perform 1 from public.families where id=home for update;
    if not exists(select 1 from public.family_members where user_id=me and family_id=home) then
      raise exception 'Family membership changed' using errcode='42501'; end if;
    select * into room from public.room_layouts where family_id=home for update;
    if not found or room.lock_user is distinct from me or room.lock_token is distinct from editor_token or
      room.lock_until is null or room.lock_until<=clock_timestamp() then reason:='lease_expired';
    elsif room.version<>expected_version then reason:='version_conflict';
    else
      reason:=public.validate_room_layout(home,proposed);
      if reason is null then
        update public.room_layouts set layout=proposed,version=version+1,edited_by=me,
          updated_at=clock_timestamp() where family_id=home returning * into room;
      end if;
    end if;
  end if;
  result:=jsonb_build_object('status',case when reason is null then 'saved' else 'rejected' end,
    'reason',reason,'request_id',request_id,'family_id',home,
    'version',room.version,'saved_layout',case when reason is null then proposed end,'edited_by',me);
  insert into public.furniture_requests values(request_id,me,home,'save',request_payload,result,clock_timestamp());
  return result;
end $$;
revoke all on function public.room_editor(text,uuid),public.save_room_layout(uuid,uuid,bigint,jsonb) from public,anon;
grant execute on function public.room_editor(text,uuid),public.save_room_layout(uuid,uuid,bigint,jsonb) to authenticated;
