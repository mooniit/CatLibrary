begin;
select no_plan();
select is((select count(*)::integer from public.furniture_products where kind='painting' and active and not is_test),15,'five bound works in each theme');
select is((select count(*)::integer from public.furniture_products where kind='frame' and active and not is_test),0,'empty frames are retired');
select is((select count(distinct geometry->>'artwork')::integer from public.furniture_products where kind='painting'),5,'five distinct paintings');
insert into auth.users(id) values('78000000-0000-0000-0000-000000000001');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"78000000-0000-0000-0000-000000000001"}',true);
select public.bootstrap_identity(); select public.create_family();
select is(jsonb_array_length(public.furniture_state()->'inventory'),0,'ordinary new households still start empty');
reset role;
insert into public.furniture_inventory(id,family_id,sku,source,source_id)
 select '78100000-0000-0000-0000-000000000001',family_id,'lunar-painting-pearl','test_grant','78200000-0000-0000-0000-000000000001'
 from public.family_members where user_id='78000000-0000-0000-0000-000000000001';
select is(public.validate_room_layout((select family_id from public.family_members where user_id='78000000-0000-0000-0000-000000000001'),
 '{"standard":"room-standard-v1","items":[{"instance_id":"78100000-0000-0000-0000-000000000001","gx":0,"gy":0,"facing":"x","slot":"art-left-back","artwork":"pearl"}]}'),null,'purchased painting fits a fixed mount');
select is(public.validate_room_layout((select family_id from public.family_members where user_id='78000000-0000-0000-0000-000000000001'),
 '{"standard":"room-standard-v1","items":[{"instance_id":"78100000-0000-0000-0000-000000000001","gx":0,"gy":0,"facing":"x","slot":"art-right-front","artwork":"mona"}]}'),'artwork_mismatch','client cannot substitute another painting');
select is(public.validate_room_layout((select family_id from public.family_members where user_id='78000000-0000-0000-0000-000000000001'),
 '{"standard":"room-standard-v1","items":[{"instance_id":"78100000-0000-0000-0000-000000000001","gx":2,"gy":0,"facing":"x","slot":"art-left-back","artwork":"pearl"}]}'),'fixed_position','painting cannot move freely');
select is(public.validate_room_layout((select family_id from public.family_members where user_id='78000000-0000-0000-0000-000000000001'),
 '{"standard":"room-standard-v1","items":[{"instance_id":"78100000-0000-0000-0000-000000000001","gx":0,"gy":0,"facing":"x","slot":"window-left","artwork":"pearl"}]}'),'invalid_slot','painting cannot use a window mount');
select * from finish();
rollback;
