begin;
select no_plan();
select is((('2026-09-16 15:59:59+00'::timestamptz
  at time zone 'Asia/Shanghai')::date+1),'2026-09-17'::date,
  'completion one second before Beijing midnight protects through Sep 17');
select is((('2026-09-16 16:00:00+00'::timestamptz
  at time zone 'Asia/Shanghai')::date+1),'2026-09-18'::date,
  'completion at Beijing midnight protects through Sep 18');
insert into auth.users(id) values
  ('58000000-0000-0000-0000-000000000001'),
  ('58000000-0000-0000-0000-000000000002'),
  ('58000000-0000-0000-0000-000000000003');
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"58000000-0000-0000-0000-000000000001"}',true);
select public.bootstrap_identity();
select public.create_family();
select public.adopt_cat('black_short','免缴猫');
reset role;
select set_config('test.single_home',family_id::text,true)
  from public.family_members where user_id='58000000-0000-0000-0000-000000000001';
update public.cats set adopted_at='2026-09-15 00:00Z'
  where family_id=current_setting('test.single_home')::uuid;
update public.wallets set miao_coins=-120
  where owner_id='58000000-0000-0000-0000-000000000001';
insert into public.repair_episodes(id,family_id,triggered_at,status,completed_at,grace_through)
  values('58000000-0000-0000-0000-000000000010',
    current_setting('test.single_home')::uuid,
    '2026-09-15 00:00Z','completed','2026-09-16 07:00Z','2026-09-17');
insert into public.repair_windows(episode_id,cycle_no,starts_at,ends_at,status)
  values('58000000-0000-0000-0000-000000000010',1,
    '2026-09-15 00:00Z','2026-09-18 00:00Z','completed');
select is(public.settle_family_day(current_setting('test.single_home')::uuid,
  '2026-09-16')->>'mode','grace','completion day is exempt');
select is(public.settle_family_day(current_setting('test.single_home')::uuid,
  '2026-09-17')->>'mode','grace','next day is also exempt');
select is((select miao_coins from public.wallets where owner_id=
  '58000000-0000-0000-0000-000000000001'),-120,
  'grace preserves old debt without new interest or cat fees');
select is((select count(*)::int from public.daily_interest_charges
  where owner_id='58000000-0000-0000-0000-000000000001'),0,
  'no interest entries during two grace days');
select is(public.settle_family_day(current_setting('test.single_home')::uuid,
  '2026-09-18')->>'mode','normal','third day resumes normal billing');
select is((select miao_coins from public.wallets where owner_id=
  '58000000-0000-0000-0000-000000000001'),-150,
  'third day deducts 12 interest and 18 of 20 cat fee to cap');
select is((select count(*)::int from public.repair_episodes
  where family_id=current_setting('test.single_home')::uuid
    and status='pending'),1,
  'single family may trigger a new repair only after grace');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"58000000-0000-0000-0000-000000000002"}',true);
select public.bootstrap_identity();
select public.create_family();
select public.adopt_cat('black_short','双人甲猫');
reset role;
insert into public.family_members(user_id,family_id)
  select '58000000-0000-0000-0000-000000000003',family_id
  from public.family_members where user_id='58000000-0000-0000-0000-000000000002';
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"58000000-0000-0000-0000-000000000003"}',true);
select public.bootstrap_identity();
select public.adopt_cat('black_short','双人乙猫');
reset role;
select set_config('test.double_home',family_id::text,true)
  from public.family_members where user_id='58000000-0000-0000-0000-000000000002';
update public.cats set adopted_at='2026-09-15 00:00Z'
  where family_id=current_setting('test.double_home')::uuid;
update public.wallets set miao_coins=-150
  where owner_id in ('58000000-0000-0000-0000-000000000002',
    '58000000-0000-0000-0000-000000000003');
select is(public.settle_family_day(current_setting('test.double_home')::uuid,
  '2026-09-16')->>'mode','repair',
  'two previously capped members trigger repair before interest and cat fees');
select is((select count(*)::int from public.daily_cat_charges
  where business_day='2026-09-16' and status='repair'
    and owner_id in ('58000000-0000-0000-0000-000000000002',
      '58000000-0000-0000-0000-000000000003')),2,
  'both cats stop incurring fees as soon as joint repair triggers');
select is((select count(*)::int from public.daily_interest_charges
  where business_day='2026-09-16' and owner_id in
    ('58000000-0000-0000-0000-000000000002',
      '58000000-0000-0000-0000-000000000003')),0,
  'joint repair stops interest at trigger zero');
select * from finish();
rollback;
