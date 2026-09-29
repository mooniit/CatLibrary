begin;
select plan(21);
insert into auth.users(id) values ('20000000-0000-0000-0000-000000000001'),('20000000-0000-0000-0000-000000000002');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"20000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select public.bootstrap_identity();
select is((public.sync_study_session('21000000-0000-0000-0000-000000000001','2026-09-01 00:00Z','2026-09-01 00:05:30Z',true)->'wallet'->>'miao_coins')::int,40,'first 5m30 pays 10');
select is((public.sync_study_session('21000000-0000-0000-0000-000000000002','2026-09-01 01:00Z','2026-09-01 01:05:40Z',true)->'wallet'->>'miao_coins')::int,52,'second 5m40 pays 12 more');
select is((select eligible_ms from public.study_days where business_day='2026-09-01'),670000::bigint,'daily progress preserves 11m10');
select is((public.sync_study_session('21000000-0000-0000-0000-000000000002','2026-09-01 01:00Z','2026-09-01 01:05:40Z',true)->'wallet'->>'miao_coins')::int,52,'lost receipt retry pays zero');
select is((select sum(miao_delta)::int from public.wallet_entries where kind='study'),22,'ledger explains cumulative issue');
select throws_ok($$select public.sync_study_session('21000000-0000-0000-0000-000000000002','2026-09-01 01:00Z','2026-09-01 01:06Z',true)$$,'22023','Confirmed session is immutable','cannot extend confirmed record');
select throws_ok($$select public.sync_study_session('21000000-0000-0000-0000-000000000003','2026-09-01 01:01Z','2026-09-01 01:02Z',true)$$,'22023','Overlapping study interval','overlap rejected');
select is((public.sync_study_session('21000000-0000-0000-0000-000000000004','2026-09-01 02:00Z','2026-09-01 04:00Z',true)->'wallet'->>'miao_coins')::int,150,'daily 120 cap includes earlier 22');
select is((select issued from public.study_days where business_day='2026-09-01'),120,'daily cap stored');
select throws_ok($$select public.sync_study_session('21000000-0000-0000-0000-000000000005','2026-09-02 00:00Z','2026-09-02 07:00Z',true)$$,'22023','Invalid study interval','single six-hour cap');
select throws_ok($$update public.study_days set issued=0$$,'42501','permission denied for table study_days','client cannot reset issue count');
select throws_ok($$insert into public.study_sessions values(gen_random_uuid(),auth.uid(),now(),now(),true)$$,'42501','permission denied for table study_sessions','direct record insert denied');
select set_config('request.jwt.claims','{"sub":"20000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select public.bootstrap_identity();
select is((select count(*)::int from public.study_sessions),0,'other user cannot read records');
select is((select count(*)::int from public.study_days),0,'other user cannot read progress');
select throws_ok($$select public.sync_study_session('21000000-0000-0000-0000-000000000001','2026-09-01 00:00Z','2026-09-01 00:05:30Z',true)$$,'42501','Session identity mismatch','cannot reuse another identity record');
reset role;
update public.wallets set miao_coins=-20 where owner_id='20000000-0000-0000-0000-000000000001';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"20000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select is((public.sync_study_session('21000000-0000-0000-0000-000000000006','2026-09-03 00:00Z','2026-09-03 00:00:59Z',true)->'wallet'->>'miao_coins')::int,-20,'59 seconds no award');
select is((public.sync_study_session('21000000-0000-0000-0000-000000000007','2026-09-03 01:00Z','2026-09-03 01:00:01Z',true)->'wallet'->>'miao_coins')::int,-18,'one more second accumulates a minute and pays debt');
select is((public.sync_study_session('21000000-0000-0000-0000-000000000008',
  (now() at time zone 'Asia/Shanghai')::date::timestamp at time zone 'Asia/Shanghai',
  ((now() at time zone 'Asia/Shanghai')::date::timestamp at time zone 'Asia/Shanghai')+interval '1 minute',false)->'wallet'->>'miao_coins')::int,-18,'today checkpoint does not pay before confirmation');
select is((public.sync_study_session('21000000-0000-0000-0000-000000000008',
  (now() at time zone 'Asia/Shanghai')::date::timestamp at time zone 'Asia/Shanghai',
  ((now() at time zone 'Asia/Shanghai')::date::timestamp at time zone 'Asia/Shanghai')+interval '1 minute',true)->'wallet'->>'miao_coins')::int,-16,'today confirmation pays two coins');
reset role;
select ok(not has_function_privilege('authenticated','public.settle_study_for_owner(uuid,timestamptz)','EXECUTE'),'client cannot choose settlement clock');
select ok(not has_function_privilege('anon','public.sync_study_session(uuid,timestamptz,timestamptz,boolean)','EXECUTE'),'anonymous callers denied');
select * from finish();
rollback;
