begin;
select no_plan();
select is((select schedule from cron.job
  where jobname='family-daily-settlement'),'1 * * * *',
  'hourly local cron invokes Beijing midnight plus missed-day catch-up');
select is(public.settle_due_family_days('2026-09-17 16:01Z'),0,
  'new billing never back-charges dates before activation');
update public.billing_activation set start_day='2026-09-15'
  where singleton=true;
insert into auth.users(id) values
  ('59000000-0000-0000-0000-000000000001'),
  ('59000000-0000-0000-0000-000000000002');
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"59000000-0000-0000-0000-000000000001"}',true);
select public.bootstrap_identity();
select public.create_family();
select public.adopt_cat('black_short','补跑猫');
reset role;
update public.families set created_at='2026-09-15 01:00Z'
  where creator_id='59000000-0000-0000-0000-000000000001';
update public.cats set adopted_at='2026-09-15 01:00Z'
  where owner_id='59000000-0000-0000-0000-000000000001';
update public.wallets set miao_coins=0
  where owner_id='59000000-0000-0000-0000-000000000001';
select is(public.settle_due_family_days('2026-09-17 16:01Z'),3,
  'hourly scheduler catches all three missed Beijing days in order');
select is((select miao_coins from public.wallets
  where owner_id='59000000-0000-0000-0000-000000000001'),-66,
  'sequential catch-up applies 20, then 2+20, then 4+20');
select is(public.settle_due_family_days('2026-09-17 17:01Z'),0,
  'next scheduler call does not repeat paid days');
select is((select count(*)::int from public.family_daily_settlements
  where family_id=(select family_id from public.family_members
    where user_id='59000000-0000-0000-0000-000000000001')),3,
  'one durable execution record exists per family day');
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"59000000-0000-0000-0000-000000000002"}',true);
select public.bootstrap_identity();
select public.create_family();
reset role;
select is(public.settle_due_family_days('2026-09-17 17:02Z'),0,
  'new family never receives pre-creation charges');
delete from public.billing_activation where singleton=true;
select throws_ok($$select public.settle_due_family_days('2026-09-17 17:03Z')$$,
  '22023','Billing activation missing',
  'missing activation marker fails safely rather than back-charging history');
select * from finish();
rollback;
