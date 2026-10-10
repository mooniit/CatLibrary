-- Purchase the artwork once; all three frame proportions use the registered plain wood skin.
insert into public.furniture_products(sku,label,theme,kind,placement,geometry,price,currency,purchase_limit,active,is_test)
 select 'painting-'||(geometry->>'artwork'),substring(label from 3),'wood','painting','art',geometry,30,'miao',1,true,false
 from public.furniture_products where theme='wood' and kind='painting' and not is_test;
update public.furniture_products set active=false where kind='painting' and sku~'^(lunar|wood|royal)-painting-' and not is_test;
-- Keep every instance and historical receipt. Families with multiple legacy themes keep those instances.
with changed as (
 update public.furniture_inventory i set sku='painting-'||(p.geometry->>'artwork')
 from public.furniture_products p where i.sku=p.sku and p.kind='painting' and p.sku~'^(lunar|wood|royal)-painting-' and not p.is_test
 returning i.family_id
)
update public.room_layouts set version=version+1,lock_user=null,lock_token=null,lock_until=null,updated_at=clock_timestamp()
 where family_id in(select family_id from changed);
