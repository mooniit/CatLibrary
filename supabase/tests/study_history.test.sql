begin;
select no_plan();
insert into auth.users(id) values ('9f600000-0000-0000-0000-000000000001'),('9f600000-0000-0000-0000-000000000002');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"9f600000-0000-0000-0000-000000000001"}',true);
select public.bootstrap_identity();
select set_config('request.jwt.claims','{"sub":"9f600000-0000-0000-0000-000000000002"}',true);
select public.bootstrap_identity();
reset role;
insert into public.study_sessions(id,owner_id,run_id,started_at,recorded_until,confirmed) values
 ('9f610000-0000-0000-0000-000000000001','9f600000-0000-0000-0000-000000000001','9f620000-0000-0000-0000-000000000001','2026-10-01 15:55Z','2026-10-01 16:05Z',true),
 ('9f610000-0000-0000-0000-000000000002','9f600000-0000-0000-0000-000000000001','9f620000-0000-0000-0000-000000000001','2026-10-01 16:10Z','2026-10-01 16:20Z',false),
 ('9f610000-0000-0000-0000-000000000003','9f600000-0000-0000-0000-000000000002','9f620000-0000-0000-0000-000000000002','2026-10-01 15:55Z','2026-10-01 16:05Z',true);
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"9f600000-0000-0000-0000-000000000001"}',true);
select is(jsonb_array_length(public.study_history()),2,'both own confirmed and interrupted evidence are available');
select is(public.study_history()->0->>'confirmed','false','newest interrupted interval stays unconfirmed');
select is(public.study_history()->1->>'activity','study','study has its own activity icon');
select is(public.study_history()->1->>'run_id','9f620000-0000-0000-0000-000000000001','paused run identity preserved');
select is((select count(*)::int from jsonb_array_elements(public.study_history()) s where s->>'owner_id'<>'9f600000-0000-0000-0000-000000000001'),0,'other member evidence is private');
reset role;
select is((select miao_coins from public.wallets where owner_id='9f600000-0000-0000-0000-000000000001'),30,'history read does not replay rewards');
select ok(not has_function_privilege('anon','public.study_history()','execute'),'unauthenticated history denied');
select ok(not has_function_privilege('authenticated','public.issue_photo_inventory(uuid,uuid)','execute'),'clients cannot auto-mint arbitrary photo rights');
select * from finish();
rollback;
