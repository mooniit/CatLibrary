begin;
select no_plan();
insert into auth.users(id) values ('76000000-0000-0000-0000-000000000001'),
 ('76000000-0000-0000-0000-000000000002'),('76000000-0000-0000-0000-000000000003');
insert into public.wallets(owner_id) select id from auth.users where id::text like '76000000-%';
insert into public.families(id,creator_id) values
 ('76100000-0000-0000-0000-000000000001','76000000-0000-0000-0000-000000000001'),
 ('76100000-0000-0000-0000-000000000002','76000000-0000-0000-0000-000000000003');
insert into public.family_members(user_id,family_id) values
 ('76000000-0000-0000-0000-000000000001','76100000-0000-0000-0000-000000000001'),
 ('76000000-0000-0000-0000-000000000002','76100000-0000-0000-0000-000000000001'),
 ('76000000-0000-0000-0000-000000000003','76100000-0000-0000-0000-000000000002');
insert into public.room_test_families values('76100000-0000-0000-0000-000000000001');
update public.room_policies set lease_seconds=120,renewal_seconds=30 where id='test';
insert into public.furniture_inventory(id,family_id,sku,source) values
 ('76200000-0000-0000-0000-000000000001','76100000-0000-0000-0000-000000000001','lunar-chair','initial'),
 ('76200000-0000-0000-0000-000000000002','76100000-0000-0000-0000-000000000001','wood-chair','initial'),
 ('76200000-0000-0000-0000-000000000003','76100000-0000-0000-0000-000000000002','royal-chair','initial'),
 ('76200000-0000-0000-0000-000000000004','76100000-0000-0000-0000-000000000001','wood-window','initial'),
 ('76200000-0000-0000-0000-000000000005','76100000-0000-0000-0000-000000000001','wood-rug','initial'),
 ('76200000-0000-0000-0000-000000000006','76100000-0000-0000-0000-000000000001','wood-desk','initial'),
 ('76200000-0000-0000-0000-000000000007','76100000-0000-0000-0000-000000000001','royal-desk','initial');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"76000000-0000-0000-0000-000000000001"}',true);
select is(public.room_editor('acquire','76300000-0000-0000-0000-000000000001')->>'status','acquired','editor acquired latest');
select is((public.room_editor('acquire','76300000-0000-0000-0000-000000000001')->>'version')::int,0,'retry acquire uses same lease');
select is(public.room_editor('renew','76300000-0000-0000-0000-000000000002')->>'reason','lease_expired','wrong token cannot renew');
select set_config('request.jwt.claims','{"sub":"76000000-0000-0000-0000-000000000002"}',true);
select is(public.room_editor('acquire','76300000-0000-0000-0000-000000000002')->>'reason','editor_busy','second member blocked from editor');
select is(jsonb_array_length(public.cats_state()->'cats'),0,'other features remain usable');
select is(jsonb_array_length(public.furniture_state()->'inventory'),6,'both members see shared inventory');
select is(public.save_room_layout('76400000-0000-0000-0000-000000000001','76300000-0000-0000-0000-000000000001',0,'{"standard":"room-standard-v1","items":[]}')->>'reason','lease_expired','cannot use other member lease');
select set_config('request.jwt.claims','{"sub":"76000000-0000-0000-0000-000000000001"}',true);
select is(public.save_room_layout('76400000-0000-0000-0000-000000000002','76300000-0000-0000-0000-000000000001',0,
 '{"standard":"room-standard-v1","items":[{"instance_id":"76200000-0000-0000-0000-000000000001","gx":1,"gy":1,"facing":"x"}]}')->>'status','saved','manual save success');
select is((public.furniture_state()->>'version')::int,1,'version incremented once');
select is(public.save_room_layout('76400000-0000-0000-0000-000000000003','76300000-0000-0000-0000-000000000001',0,'{"standard":"room-standard-v1","items":[]}')->>'reason','version_conflict','old version cannot overwrite');
select is(public.save_room_layout('76400000-0000-0000-0000-000000000004','76300000-0000-0000-0000-000000000001',1,
 '{"standard":"room-standard-v1","items":[{"instance_id":"76200000-0000-0000-0000-000000000003","gx":1,"gy":1,"facing":"x"}]}')->>'reason','inventory_missing','outside family inventory denied');
select is(public.save_room_layout('76400000-0000-0000-0000-000000000005','76300000-0000-0000-0000-000000000001',1,
 '{"standard":"room-standard-v1","items":[{"instance_id":"76200000-0000-0000-0000-000000000001","gx":1,"gy":1,"facing":"x"},{"instance_id":"76200000-0000-0000-0000-000000000001","gx":2,"gy":1,"facing":"x"}]}')->>'reason','duplicate_instance','cannot duplicate same item');
select is(public.save_room_layout('76400000-0000-0000-0000-000000000006','76300000-0000-0000-0000-000000000001',1,
 '{"standard":"room-standard-v1","items":[{"instance_id":"76200000-0000-0000-0000-000000000001","gx":1,"gy":1,"facing":"x"},{"instance_id":"76200000-0000-0000-0000-000000000002","gx":1,"gy":1,"facing":"y"}]}')->>'reason','cell_conflict','overlap denied');
select is(public.save_room_layout('76400000-0000-0000-0000-000000000007','76300000-0000-0000-0000-000000000001',1,
 '{"standard":"room-standard-v1","items":[{"instance_id":"76200000-0000-0000-0000-000000000001","gx":8,"gy":1,"facing":"x"}]}')->>'reason','out_of_bounds','boundary denied');
select is(public.save_room_layout('76400000-0000-0000-0000-000000000008','76300000-0000-0000-0000-000000000001',1,
 '{"standard":"room-standard-v1","items":[{"instance_id":"76200000-0000-0000-0000-000000000004","gx":0,"gy":0,"facing":"x","slot":"window-left"},{"instance_id":"76200000-0000-0000-0000-000000000004","gx":0,"gy":0,"facing":"x","slot":"window-right"}]}')->>'reason','duplicate_instance','one window cannot occupy both mounts');
select is(public.save_room_layout('76400000-0000-0000-0000-000000000009','76300000-0000-0000-0000-000000000001',1,
 '{"standard":"room-standard-v1","items":[{"instance_id":"76200000-0000-0000-0000-000000000005","gx":1,"gy":0,"facing":"x","slot":"rug"}]}')->>'reason','fixed_position','rug cannot move');
select is(public.save_room_layout('76400000-0000-0000-0000-000000000010','76300000-0000-0000-0000-000000000001',1,
 '{"standard":"room-standard-v1","items":[{"instance_id":"76200000-0000-0000-0000-000000000006","gx":0,"gy":0,"facing":"x"},{"instance_id":"76200000-0000-0000-0000-000000000007","gx":4,"gy":0,"facing":"x"}]}')->>'reason','category_limit','desk limit spans styles');
select is((public.furniture_state()->>'version')::int,1,'invalid layouts leave version unchanged');
select public.room_editor('release','76300000-0000-0000-0000-000000000001');
select set_config('request.jwt.claims','{"sub":"76000000-0000-0000-0000-000000000002"}',true);
select is(public.room_editor('acquire','76300000-0000-0000-0000-000000000002')->>'status','acquired','partner acquires released lease');
select is(public.save_room_layout('76400000-0000-0000-0000-000000000011','76300000-0000-0000-0000-000000000002',1,'{"standard":"room-standard-v1","items":[]}')->>'status','saved','partner saves subsequent version');
select set_config('request.jwt.claims','{"sub":"76000000-0000-0000-0000-000000000001"}',true);
select is((public.furniture_request('76400000-0000-0000-0000-000000000002')->>'version')::int,1,'lost response lookup returns original version after partner saved');
select is((public.save_room_layout('76400000-0000-0000-0000-000000000002','76300000-0000-0000-0000-000000000001',0,
 '{"standard":"room-standard-v1","items":[{"instance_id":"76200000-0000-0000-0000-000000000001","gx":1,"gy":1,"facing":"x"}]}')->>'version')::int,1,'retry still returns original receipt despite expired lease');
select is((public.furniture_state()->>'version')::int,2,'retry does not overwrite partner version');
reset role;
update public.room_layouts set lock_until=clock_timestamp()-interval '1 second' where family_id='76100000-0000-0000-0000-000000000001';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"76000000-0000-0000-0000-000000000002"}',true);
select is(public.room_editor('renew','76300000-0000-0000-0000-000000000002')->>'reason','lease_expired','cannot revive expired token by renew');
select is(public.save_room_layout('76400000-0000-0000-0000-000000000012','76300000-0000-0000-0000-000000000002',2,'{"standard":"room-standard-v1","items":[]}')->>'reason','lease_expired','expired lease cannot save');
select set_config('request.jwt.claims','{"sub":"76000000-0000-0000-0000-000000000003"}',true);
select is(jsonb_array_length(public.furniture_state()->'inventory'),1,'outsider cannot enumerate family inventory');
select is(public.room_editor('acquire','76300000-0000-0000-0000-000000000003')->>'status','acquired','confirmed production lease available in independent household');
select throws_ok($$select public.furniture_request('76400000-0000-0000-0000-000000000002')$$,'42501','Request belongs to another user','partner receipts private to request user');
reset role;
select ok(not has_function_privilege('authenticated','public.validate_room_layout(uuid,jsonb)','EXECUTE'),'internal validator inaccessible');
select ok(not has_table_privilege('authenticated','public.room_layouts','UPDATE'),'direct writes denied');
select * from finish();
rollback;
