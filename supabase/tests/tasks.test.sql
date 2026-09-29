begin;
select no_plan();
insert into auth.users(id) values
  ('30000000-0000-0000-0000-000000000001'),
  ('30000000-0000-0000-0000-000000000002'),
  ('30000000-0000-0000-0000-000000000003');
insert into public.families(id,creator_id) values
  ('31000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001');
insert into public.family_members(user_id,family_id) values
  ('30000000-0000-0000-0000-000000000001','31000000-0000-0000-0000-000000000001'),
  ('30000000-0000-0000-0000-000000000002','31000000-0000-0000-0000-000000000001');

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"30000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select public.bootstrap_identity();
select is((public.sync_task_session('32000000-0000-0000-0000-000000000001','language',
  '2026-09-01 00:00Z','2026-09-01 00:06Z',null,false)->'wallet'->>'eagle_pounds')::int,
  0,'an unconfirmed six-minute task pays nothing');
select throws_ok($$select public.sync_task_session('32000000-0000-0000-0000-000000000001',
  'language','2026-09-01 00:00Z','2026-09-01 00:06Z',
  '30000000-0000-0000-0000-000000000001/32000000-0000-0000-0000-000000000001',true)$$,
  '22023','Photo upload is not complete','confirmation rejects a missing photo');
select throws_ok($$select public.sync_task_session('32000000-0000-0000-0000-000000000001',
  'language','2026-09-01 00:00Z','2026-09-01 00:06Z',
  '30000000-0000-0000-0000-000000000003/32000000-0000-0000-0000-000000000001',true)$$,
  '22023','Invalid photo path','photo path cannot claim another owner');
reset role;
insert into storage.objects(bucket_id,name) values
  ('task-photos','30000000-0000-0000-0000-000000000001/32000000-0000-0000-0000-000000000001');
set local role authenticated;
select is((public.sync_task_session('32000000-0000-0000-0000-000000000001','language',
  '2026-09-01 00:00Z','2026-09-01 00:06Z',
  '30000000-0000-0000-0000-000000000001/32000000-0000-0000-0000-000000000001',true)
  ->'wallet'->>'eagle_pounds')::int,0,'six minutes is below the ten-minute gate');
select throws_ok($$select public.sync_task_session('32000000-0000-0000-0000-000000000001',
  'language','2026-09-01 00:00Z','2026-09-01 00:07Z',
  '30000000-0000-0000-0000-000000000001/32000000-0000-0000-0000-000000000001',true)$$,
  '22023','Confirmed task is immutable','confirmed evidence cannot grow');
select is((public.sync_task_session('32000000-0000-0000-0000-000000000002','language',
  '2026-09-01 01:00Z','2026-09-01 01:05Z',null,false)->'wallet'->>'eagle_pounds')::int,
  0,'second activity interval still waits for photo');
reset role;
insert into storage.objects(bucket_id,name) values
  ('task-photos','30000000-0000-0000-0000-000000000001/32000000-0000-0000-0000-000000000002');
set local role authenticated;
select is((public.sync_task_session('32000000-0000-0000-0000-000000000002','language',
  '2026-09-01 01:00Z','2026-09-01 01:05Z',
  '30000000-0000-0000-0000-000000000001/32000000-0000-0000-0000-000000000002',true)
  ->'wallet'->>'eagle_pounds')::int,2,'6m + 5m language pays two eagle pounds');
select is((public.sync_task_session('32000000-0000-0000-0000-000000000002','language',
  '2026-09-01 01:00Z','2026-09-01 01:05Z',
  '30000000-0000-0000-0000-000000000001/32000000-0000-0000-0000-000000000002',true)
  ->'wallet'->>'eagle_pounds')::int,2,'retry cannot duplicate special currency');
select is((public.sync_task_session('32000000-0000-0000-0000-000000000002','language',
  '2026-09-01 01:00Z','2026-09-01 01:05Z',null,false)
  ->'wallet'->>'eagle_pounds')::int,2,'lost-response preflight is idempotent');
select is((select eligible_ms from public.task_days where activity='language'
  and business_day='2026-09-01'),660000::bigint,'same-activity daily progress is cumulative');
select is((select sum(eagle_delta)::int from public.wallet_entries where kind='task_language'),
  2,'special currency has an auditable wallet entry');
select public.sync_task_session('32000000-0000-0000-0000-000000000003','exercise',
  '2026-09-01 02:00Z','2026-09-01 02:10Z',null,false);
reset role;
insert into storage.objects(bucket_id,name) values
  ('task-photos','30000000-0000-0000-0000-000000000001/32000000-0000-0000-0000-000000000003');
set local role authenticated;
select is((public.sync_task_session('32000000-0000-0000-0000-000000000003','exercise',
  '2026-09-01 02:00Z','2026-09-01 02:10Z',
  '30000000-0000-0000-0000-000000000001/32000000-0000-0000-0000-000000000003',true)
  ->'wallet'->>'gems')::int,2,'exercise earns only its own gems at ten minutes');
select is((select miao_coins from public.wallets where owner_id=auth.uid()),30,
  'regular activities do not stack miao coins');
select throws_ok($$select public.sync_study_session('32000000-0000-0000-0000-000000000004',
  '2026-09-01 02:05Z','2026-09-01 02:06Z',true)$$,
  '22023','Overlapping task interval','study cannot overlap a task interval');
select throws_ok($$select public.sync_task_session('32000000-0000-0000-0000-000000000004',
  'language','2026-09-01 02:05Z','2026-09-01 02:06Z',null,false)$$,
  '22023','Overlapping task interval','tasks cannot overlap each other');
select is(jsonb_array_length(public.task_feed()),3,'owner sees own three confirmed photos');
select is((select count(*)::int from storage.objects where bucket_id='task-photos'),3,
  'owner may read own private photos');
select set_config('request.jwt.claims','{"sub":"30000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select public.bootstrap_identity();
select is(jsonb_array_length(public.task_feed()),3,'family member sees confirmed activity photos');
select is((select count(*)::int from storage.objects where bucket_id='task-photos'),3,
  'family member can read private photo objects');
select set_config('request.jwt.claims','{"sub":"30000000-0000-0000-0000-000000000003","role":"authenticated"}',true);
select public.bootstrap_identity();
select is(jsonb_array_length(public.task_feed()),0,'outside user sees no activity photos');
select is((select count(*)::int from storage.objects where bucket_id='task-photos'),0,
  'outside user cannot read private photo objects');
select set_config('request.jwt.claims','{"sub":"30000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select public.sync_task_session('32000000-0000-0000-0000-000000000005','language',
  '2026-09-02 15:55Z','2026-09-02 16:05Z',null,false);
reset role;
insert into storage.objects(bucket_id,name) values
  ('task-photos','30000000-0000-0000-0000-000000000001/32000000-0000-0000-0000-000000000005');
set local role authenticated;
select is((public.sync_task_session('32000000-0000-0000-0000-000000000005','language',
  '2026-09-02 15:55Z','2026-09-02 16:05Z',
  '30000000-0000-0000-0000-000000000001/32000000-0000-0000-0000-000000000005',true)
  ->'wallet'->>'eagle_pounds')::int,2,'cross-midnight 5m + 5m does not combine across days');
select results_eq($$select business_day,eligible_ms from public.task_days
  where owner_id=auth.uid() and activity='language' and business_day in ('2026-09-02','2026-09-03')
  order by business_day$$,
  $$values ('2026-09-02'::date,300000::bigint),('2026-09-03'::date,300000::bigint)$$,
  'confirmed cross-midnight photo task splits into two Beijing days');
select * from finish();
rollback;
