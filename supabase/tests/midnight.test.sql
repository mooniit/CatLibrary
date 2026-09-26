begin;
select plan(7);
insert into auth.users(id) values('22000000-0000-0000-0000-000000000001');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"22000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select public.bootstrap_identity();
select is((public.sync_study_session('23000000-0000-0000-0000-000000000001','2026-09-01 15:59Z','2026-09-01 16:01Z',true)->'wallet'->>'miao_coins')::int,34,'23:59 to 00:01 pays independent two coins each day');
select is((select issued from public.study_days where business_day='2026-09-01'),2,'previous day receives one minute');
select is((select issued from public.study_days where business_day='2026-09-02'),2,'next day receives one minute');
select is((public.sync_study_session('23000000-0000-0000-0000-000000000002','2026-09-03 15:59:30Z','2026-09-03 16:00:30Z',true)->'wallet'->>'miao_coins')::int,34,'thirty seconds on each day never combine across midnight');
-- Old unconfirmed checkpoint is eligible without final confirmation.
select is((public.sync_study_session('23000000-0000-0000-0000-000000000003','2026-09-04 15:00Z','2026-09-04 16:00Z',false)->'wallet'->>'miao_coins')::int,154,'past-day durable checkpoint settles without confirmation');
select is((public.sync_study_session('23000000-0000-0000-0000-000000000003','2026-09-04 15:00Z','2026-09-04 16:00Z',true)->'wallet'->>'miao_coins')::int,154,'final confirmation cannot pay prior day twice');
reset role;
select public.settle_study_midnight();
set local role authenticated;
select is((public.study_state()->'wallet'->>'miao_coins')::int,154,'scheduled retry idempotent');
select * from finish();
rollback;
