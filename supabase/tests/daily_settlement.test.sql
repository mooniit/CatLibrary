begin;
select no_plan();
insert into auth.users(id) values('52000000-0000-0000-0000-000000000001');
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"52000000-0000-0000-0000-000000000001"}',true);
select public.bootstrap_identity();
select public.create_family();
select public.adopt_cat('black_short','结算猫');
reset role;
select set_config('test.home',family_id::text,true) from public.family_members
  where user_id='52000000-0000-0000-0000-000000000001';
select set_config('test.cat',id::text,true) from public.cats where name='结算猫';
update public.cats set adopted_at='2026-08-31 16:00Z'
  where id=current_setting('test.cat')::uuid;
update public.wallets set miao_coins=0
  where owner_id='52000000-0000-0000-0000-000000000001';

select is(public.settle_family_day(current_setting('test.home')::uuid,'2026-09-01')->>'status',
  'settled','first billing day runs');
select is((select miao_coins from public.wallets
  where owner_id='52000000-0000-0000-0000-000000000001'),-20,
  'zero balance and one unfed cat becomes -20');
select is(public.settle_family_day(current_setting('test.home')::uuid,'2026-09-01')->>'status',
  'already_settled','same family day is idempotent');
select is((select miao_coins from public.wallets
  where owner_id='52000000-0000-0000-0000-000000000001'),-20,
  'retry does not deduct again');
select public.settle_family_day(current_setting('test.home')::uuid,'2026-09-02');
select is((select miao_coins from public.wallets
  where owner_id='52000000-0000-0000-0000-000000000001'),-42,
  'next billing day charges two interest then 20 cat fee');
select results_eq($$select due,paid from public.daily_interest_charges
  where business_day='2026-09-02'$$,
  $$values (2,2)$$,'interest is 10 percent of old debt, rounded down');

update public.wallets set miao_coins=-128
  where owner_id='52000000-0000-0000-0000-000000000001';
select public.settle_family_day(current_setting('test.home')::uuid,'2026-09-03');
select results_eq($$select due,paid from public.daily_interest_charges
  where business_day='2026-09-03'$$,
  $$values (12,12)$$,'interest brings wallet to -140 before cat charge');
select results_eq($$select due,paid from public.daily_cat_charges
  where business_day='2026-09-03'$$,
  $$values (20,10)$$,'20 owed at -140 pays only ten and cancels ten');
select is((select miao_coins from public.wallets
  where owner_id='52000000-0000-0000-0000-000000000001'),-150,
  'wallet is capped at -150');

select public.settle_family_day(current_setting('test.home')::uuid,'2026-09-04');
select results_eq($$select due,paid,status from public.daily_cat_charges
  where business_day='2026-09-04'$$,
  $$values (0,0,'repair'::text)$$,'repairing family incurs no automatic fee');
select is((select miao_coins from public.wallets
  where owner_id='52000000-0000-0000-0000-000000000001'),-150,
  'repair stops interest and preserves debt');

update public.wallets set miao_coins=-20
  where owner_id='52000000-0000-0000-0000-000000000001';
insert into public.study_sessions(id,owner_id,started_at,recorded_until,confirmed)
  values('52000000-0000-0000-0000-000000000010',
    '52000000-0000-0000-0000-000000000001',
    '2026-09-05 00:00Z','2026-09-05 00:01Z',true);
select public.settle_family_day(current_setting('test.home')::uuid,'2026-09-05');
select is((select miao_coins from public.wallets
  where owner_id='52000000-0000-0000-0000-000000000001'),-18,
  'pre-repair eligible reward pays debt but repair stops fees');
select is((select count(*)::int from public.family_daily_settlements
  where family_id=current_setting('test.home')::uuid),5,
  'each date has one durable execution record');

insert into auth.users(id) values('52000000-0000-0000-0000-000000000002');
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"52000000-0000-0000-0000-000000000002"}',true);
select public.bootstrap_identity();
select public.create_family();
select public.adopt_cat('black_short','正常结算猫');
reset role;
update public.cats set adopted_at='2026-09-04 16:00Z'
  where name='正常结算猫';
update public.wallets set miao_coins=-20
  where owner_id='52000000-0000-0000-0000-000000000002';
insert into public.study_sessions(id,owner_id,started_at,recorded_until,confirmed)
  values('52000000-0000-0000-0000-000000000020',
    '52000000-0000-0000-0000-000000000002',
    '2026-09-05 00:00Z','2026-09-05 00:01Z',true);
select public.settle_family_day((select family_id from public.family_members
  where user_id='52000000-0000-0000-0000-000000000002'),'2026-09-05');
select is((select balance_after_reward from public.daily_interest_charges
  where owner_id='52000000-0000-0000-0000-000000000002'
    and business_day='2026-09-05'),-18,
  'eligible reward reduces normal debt before interest');
select is((select miao_coins from public.wallets
  where owner_id='52000000-0000-0000-0000-000000000002'),-39,
  'normal reward, interest, then cat fee results in -39');
insert into public.cat_feedings(cat_id,business_day,payer_id)
  select id,'2026-09-06','52000000-0000-0000-0000-000000000002'
  from public.cats where name='正常结算猫';
select public.settle_family_day((select family_id from public.family_members
  where user_id='52000000-0000-0000-0000-000000000002'),'2026-09-06');
select results_eq($$select due,paid,status from public.daily_cat_charges
  where business_day='2026-09-06' and owner_id=
    '52000000-0000-0000-0000-000000000002'$$,
  $$values (0,0,'fed'::text)$$,'fed cat incurs no automatic fee');
select ok(not has_function_privilege('authenticated',
  'public.settle_family_day(uuid,date)','EXECUTE'),
  'clients cannot run or backdate settlement');
select * from finish();
rollback;
