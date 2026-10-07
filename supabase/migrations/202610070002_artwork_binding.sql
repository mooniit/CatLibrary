-- Paintings are purchased with their fixed frame; old receipts remain immutable.
update public.furniture_products set active=false where kind='frame' and not is_test;
insert into public.furniture_products(sku,label,theme,kind,placement,geometry,price,currency,purchase_limit,active,is_test) values
('lunar-painting-starry','月轨爪印星夜','lunar','painting','art','{"template":"landscape","artwork":"starry"}',45,'miao',1,true,false),
('lunar-painting-mona','月轨猫娜丽莎','lunar','painting','art','{"template":"portrait","artwork":"mona"}',45,'miao',1,true,false),
('lunar-painting-scream','月轨喵的呐喊','lunar','painting','art','{"template":"portrait","artwork":"scream"}',45,'miao',1,true,false),
('lunar-painting-pearl','月轨戴珍珠耳环的猫','lunar','painting','art','{"template":"portrait","artwork":"pearl"}',45,'miao',1,true,false),
('lunar-painting-sunflowers','月轨向日葵','lunar','painting','art','{"template":"square","artwork":"sunflowers"}',45,'miao',1,true,false),
('wood-painting-starry','木质爪印星夜','wood','painting','art','{"template":"landscape","artwork":"starry"}',30,'miao',1,true,false),
('wood-painting-mona','木质猫娜丽莎','wood','painting','art','{"template":"portrait","artwork":"mona"}',30,'miao',1,true,false),
('wood-painting-scream','木质喵的呐喊','wood','painting','art','{"template":"portrait","artwork":"scream"}',30,'miao',1,true,false),
('wood-painting-pearl','木质戴珍珠耳环的猫','wood','painting','art','{"template":"portrait","artwork":"pearl"}',30,'miao',1,true,false),
('wood-painting-sunflowers','木质向日葵','wood','painting','art','{"template":"square","artwork":"sunflowers"}',30,'miao',1,true,false),
('royal-painting-starry','皇家爪印星夜','royal','painting','art','{"template":"landscape","artwork":"starry"}',60,'miao',1,true,false),
('royal-painting-mona','皇家猫娜丽莎','royal','painting','art','{"template":"portrait","artwork":"mona"}',60,'miao',1,true,false),
('royal-painting-scream','皇家喵的呐喊','royal','painting','art','{"template":"portrait","artwork":"scream"}',60,'miao',1,true,false),
('royal-painting-pearl','皇家戴珍珠耳环的猫','royal','painting','art','{"template":"portrait","artwork":"pearl"}',60,'miao',1,true,false),
('royal-painting-sunflowers','皇家向日葵','royal','painting','art','{"template":"square","artwork":"sunflowers"}',60,'miao',1,true,false);

-- Preserve instance IDs, family ownership and provenance when retiring empty frames.
do $$ declare i record; chosen text; homes uuid[]:='{}'; begin
 for i in select inv.*,p.theme,p.geometry from public.furniture_inventory inv join public.furniture_products p using(sku) where p.kind='frame' and not p.is_test loop
  select e->>'artwork' into chosen from public.room_layouts l cross join lateral jsonb_array_elements(l.layout->'items') e
    where l.family_id=i.family_id and e->>'instance_id'=i.id::text;
  chosen:=coalesce(chosen,case i.geometry->>'template' when 'portrait' then 'pearl' when 'square' then 'sunflowers' else 'starry' end);
  update public.furniture_inventory set sku=i.theme||'-painting-'||chosen where id=i.id;
  homes:=array_append(homes,i.family_id);
 end loop;
 -- Explicit version change protects drafts/leases created under the old catalog.
 update public.room_layouts l set layout=jsonb_set(l.layout,'{items}',coalesce((select jsonb_agg(
  case when p.geometry ? 'artwork' then jsonb_set(e,'{artwork}',p.geometry->'artwork') else e end)
  from jsonb_array_elements(l.layout->'items') e join public.furniture_inventory inv on inv.id::text=e->>'instance_id'
  join public.furniture_products p using(sku)), '[]'::jsonb)), version=version+1,lock_user=null,lock_token=null,lock_until=null,updated_at=clock_timestamp()
 where family_id=any(homes);
end $$;

alter function public.validate_room_layout(uuid,jsonb) rename to validate_room_layout_geometry;
create function public.validate_room_layout(home uuid,proposed jsonb) returns text
language plpgsql security definer set search_path='' as $$
declare reason text; item jsonb; bound text;
begin
 reason:=public.validate_room_layout_geometry(home,proposed);
 if reason is not null then return reason; end if;
 for item in select value from jsonb_array_elements(proposed->'items') loop
  select p.geometry->>'artwork' into bound from public.furniture_inventory i join public.furniture_products p using(sku)
    where i.id::text=item->>'instance_id' and i.family_id=home;
  if bound is not null and item->>'artwork' is distinct from bound then return 'artwork_mismatch'; end if;
 end loop;
 return null;
end $$;
revoke all on function public.validate_room_layout(uuid,jsonb),public.validate_room_layout_geometry(uuid,jsonb) from public,anon,authenticated;
