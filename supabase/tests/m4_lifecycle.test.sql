begin;
select no_plan();
insert into auth.users(id) values
  ('61000000-0000-0000-0000-000000000001'),
  ('61000000-0000-0000-0000-000000000002');
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"61000000-0000-0000-0000-000000000001"}',true);
select public.bootstrap_identity();
select public.create_family();
select public.adopt_cat('black_short','甲猫');
reset role;
insert into public.family_members(user_id,family_id)
  select '61000000-0000-0000-0000-000000000002',family_id
  from public.family_members where user_id='61000000-0000-0000-0000-000000000001';
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"61000000-0000-0000-0000-000000000002"}',true);
select public.bootstrap_identity();
select public.adopt_cat('black_short','乙猫');
reset role;
select set_config('test.home',family_id::text,true) from public.family_members
  where user_id='61000000-0000-0000-0000-000000000001';
select set_config('test.day1',
  ((clock_timestamp() at time zone 'Asia/Shanghai')::date-3)::text,true);
update public.cats set adopted_at=
  current_setting('test.day1')::date::timestamp at time zone 'Asia/Shanghai'
  where family_id=current_setting('test.home')::uuid;
update public.wallets set miao_coins=case when owner_id=
  '61000000-0000-0000-0000-000000000001' then -130 else -80 end
  where owner_id in ('61000000-0000-0000-0000-000000000001',
    '61000000-0000-0000-0000-000000000002');
select is(public.settle_family_day(current_setting('test.home')::uuid,
  current_setting('test.day1')::date)->>'mode','normal',
  'first day is normal, A reaches debt cap');
select results_eq($$select miao_coins from public.wallets where owner_id in
  ('61000000-0000-0000-0000-000000000001',
   '61000000-0000-0000-0000-000000000002') order by owner_id$$,
  $$values (-150),(-108)$$,'day one balances match interest and own cat fees');
select is(public.settle_family_day(current_setting('test.home')::uuid,
  current_setting('test.day1')::date+1)->>'mode','normal',
  'second day allows proxy after B own fees');
select is((select paid from public.daily_cat_charges where owner_id=
  '61000000-0000-0000-0000-000000000001' and business_day=
  current_setting('test.day1')::date+1),12,
  'B pays only 12 of A cat fee before reaching own -150 cap');
select is((select count(*)::int from public.proxy_payment_notices where payer_id=
  '61000000-0000-0000-0000-000000000002'),1,
  'proxy payment creates one daily notice');
select is(public.settle_family_day(current_setting('test.home')::uuid,
  current_setting('test.day1')::date+2)->>'mode','repair',
  'third day starts joint repair before any new fees');
select is((select count(*)::int from public.daily_interest_charges
  where business_day=current_setting('test.day1')::date+2
  and owner_id in ('61000000-0000-0000-0000-000000000001',
    '61000000-0000-0000-0000-000000000002')),0,
  'repair trigger stops both members interest immediately');
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"61000000-0000-0000-0000-000000000001"}',true);
select is(public.repair_state()->>'status','active',
  'first member online starts a shared 72-hour window');
reset role;
update public.repair_windows set starts_at=now()-interval '3 hours',
  ends_at=now()+interval '69 hours'
  where episode_id=(select id from public.repair_episodes
    where family_id=current_setting('test.home')::uuid and status='active');
insert into public.study_sessions(id,owner_id,started_at,recorded_until,confirmed)
  select '61000000-0000-0000-0000-000000000011',
    '61000000-0000-0000-0000-000000000001',
    starts_at+interval '30 minutes',starts_at+interval '90 minutes',true
  from public.repair_windows where cycle_no=1 and episode_id in
    (select id from public.repair_episodes where family_id=current_setting('test.home')::uuid);
insert into public.study_sessions(id,owner_id,started_at,recorded_until,confirmed)
  select '61000000-0000-0000-0000-000000000012',
    '61000000-0000-0000-0000-000000000002',
    starts_at+interval '90 minutes',starts_at+interval '150 minutes',true
  from public.repair_windows where cycle_no=1 and episode_id in
    (select id from public.repair_episodes where family_id=current_setting('test.home')::uuid);
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"61000000-0000-0000-0000-000000000002"}',true);
select is(public.repair_state()->>'status','completed',
  'second member sees shared two-hour completion');
reset role;
select results_eq($$select miao_coins from public.wallets where owner_id in
  ('61000000-0000-0000-0000-000000000001',
   '61000000-0000-0000-0000-000000000002') order by owner_id$$,
  $$values (-150),(-150)$$,'repair completion preserves both debts');
select is(public.settle_family_day(current_setting('test.home')::uuid,
  (clock_timestamp() at time zone 'Asia/Shanghai')::date)->>'mode','grace',
  'completion day has no fees');
select is(public.settle_family_day(current_setting('test.home')::uuid,
  (clock_timestamp() at time zone 'Asia/Shanghai')::date+1)->>'mode','grace',
  'following Beijing day has no fees');
select is(public.settle_family_day(current_setting('test.home')::uuid,
  (clock_timestamp() at time zone 'Asia/Shanghai')::date+2)->>'mode','repair',
  'third Beijing day resumes normal trigger rule; both still capped');
select * from finish();
rollback;
