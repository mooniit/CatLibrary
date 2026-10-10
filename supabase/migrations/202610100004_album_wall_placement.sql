-- Album rights become inventory only when explicitly requested; never a second purchase.
insert into public.furniture_products(sku,label,theme,kind,placement,geometry,purchase_limit)
 select 'photo-'||a.appearance||'-'||d.id,a.label||' · '||d.label,'wood','photo','art',
 jsonb_build_object('template','landscape','artwork',a.prefix||initcap(d.id)),1
 from public.travel_destinations d cross join(values('black_short','三花旅行照片','calico'),('light_long','长毛猫旅行照片','longhair')) a(appearance,label,prefix);
create table public.photo_wall_inventory (
 id uuid primary key default gen_random_uuid(), family_id uuid not null references public.families(id),
 visit_id uuid unique references public.cat_travel_visits(id), unlock_id uuid unique references public.test_photo_unlocks(id),
 inventory_id uuid not null unique references public.furniture_inventory(id),check(num_nonnulls(visit_id,unlock_id)=1)
);
alter table public.photo_wall_inventory enable row level security;
revoke all on public.photo_wall_inventory from public,anon,authenticated,service_role;
alter table public.furniture_inventory drop constraint furniture_inventory_source_check;
alter table public.furniture_inventory add constraint furniture_inventory_source_check check(source in('purchase','initial','souvenir','test_grant','photo'));
create function public.prepare_photo_placement(photo_id uuid,photo_source text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare me uuid:=auth.uid(); home uuid; photo jsonb; instance uuid; owner_id uuid; cat uuid; sku_key text;
begin
 if me is null then raise exception 'Authentication required' using errcode='42501'; end if;
 if photo_id is null or photo_source is null or photo_source not in('travel','test_grant') then raise exception 'Invalid photo request' using errcode='22023'; end if;
 select family_id into home from public.family_members where user_id=me;
 perform 1 from public.families where id=home for update;
 select value into photo from jsonb_array_elements(public.family_album()->'photos')
 where value->>'id'=photo_id::text and coalesce(value->>'source','travel')=photo_source;
 if photo is null then raise exception 'Photo is not available in your album' using errcode='42501'; end if;
 select inventory_id into instance from public.photo_wall_inventory w where w.family_id=home
 and ((photo_source='travel' and w.visit_id=photo_id) or (photo_source='test_grant' and w.unlock_id=photo_id));
 if instance is null then
  sku_key:='photo-'||(photo->>'appearance')||'-'||(photo->>'destination');
  if not exists(select 1 from public.furniture_products where sku=sku_key and kind='photo' and not active) then raise exception 'Photo artwork unavailable' using errcode='22023'; end if;
  cat:=(photo->>'cat_id')::uuid;
  owner_id:=me;
  if photo_source='travel' then select c.owner_id into strict owner_id from public.cats c where c.id=cat and c.family_id=home; end if;
  insert into public.furniture_inventory(family_id,sku,purchased_by,source,source_id,source_cat_id)
   values(home,sku_key,owner_id,'photo',photo_id,cat) returning id into instance;
  insert into public.photo_wall_inventory(family_id,visit_id,unlock_id,inventory_id)
   values(home,case when photo_source='travel' then photo_id end,case when photo_source='test_grant' then photo_id end,instance);
 end if;
 return jsonb_build_object('status','ready','family_id',home,'inventory_id',instance);
end $$;
revoke all on function public.prepare_photo_placement(uuid,text) from public,anon;
grant execute on function public.prepare_photo_placement(uuid,text) to authenticated;

create or replace function public.validate_room_layout_geometry(home uuid, proposed jsonb) returns text
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
      if product.placement='art' and (item->>'artwork' is null or item->>'artwork' not in ('starry','mona','scream','pearl','sunflowers','calicoPalace','calicoLouvre','calicoFuji','calicoPyramid','calicoEiffel','calicoLiberty','longhairPalace','longhairLouvre','longhairFuji','longhairPyramid','longhairEiffel','longhairLiberty')) then return 'invalid_artwork'; end if;
    end if;
  end loop;
  return null;
exception when invalid_text_representation or numeric_value_out_of_range then return 'invalid_layout';
end $$;
revoke all on function public.validate_room_layout_geometry(uuid,jsonb) from public,anon,authenticated;
