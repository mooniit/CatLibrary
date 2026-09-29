begin;
select no_plan();
update public.billing_activation set start_day='2026-09-15'
  where singleton=true;
insert into auth.users(id) values
  ('67000000-0000-0000-0000-000000000001'),
  ('67000000-0000-0000-0000-000000000002');
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"67000000-0000-0000-0000-000000000001"}',true);
select public.create_family();
reset role;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"67000000-0000-0000-0000-000000000002"}',true);
select public.bootstrap_identity();
select public.create_family();
reset role;
update public.families set created_at='2026-09-15 01:00Z'
  where creator_id in ('67000000-0000-0000-0000-000000000001',
    '67000000-0000-0000-0000-000000000002');
select is(public.settle_due_family_days('2026-09-17 16:01Z'),3,
  'broken family does not prevent three days for healthy family');
select is((select count(*)::int from public.family_settlement_failures
  where family_id=(select family_id from public.family_members
    where user_id='67000000-0000-0000-0000-000000000001')),1,
  'first failed day is visible and later days wait in order');
select is((select count(*)::int from public.family_daily_settlements
  where family_id=(select family_id from public.family_members
    where user_id='67000000-0000-0000-0000-000000000002')),3,
  'healthy family has three durable daily records');
select is(public.settle_due_family_days('2026-09-17 17:01Z'),0,
  'retry does not repeat healthy-family bills');
select is((select attempts from public.family_settlement_failures
  where family_id=(select family_id from public.family_members
    where user_id='67000000-0000-0000-0000-000000000001')),
  2,'failed family records retry count without blocking others');
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"67000000-0000-0000-0000-000000000001"}',true);
select public.bootstrap_identity();
reset role;
select is(public.settle_due_family_days('2026-09-17 18:01Z'),3,
  'once missing wallet exists, failed family catches up in order');
select is((select count(*)::int from public.family_settlement_failures
  where family_id=(select family_id from public.family_members
    where user_id='67000000-0000-0000-0000-000000000001')),0,
  'successful retry clears the failure record');
select * from finish();
rollback;
