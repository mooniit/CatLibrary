begin;
select no_plan();
insert into auth.users(id) values
  ('51000000-0000-0000-0000-000000000001'),
  ('51000000-0000-0000-0000-000000000002'),
  ('51000000-0000-0000-0000-000000000003');
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"51000000-0000-0000-0000-000000000001"}',true);
select public.bootstrap_identity();
select public.create_family();
select public.adopt_cat('black_short','第一只');
select public.adopt_cat('light_long','第二只');
reset role;
select set_config('test.first_cat',id::text,true)
  from public.cats where name='第一只';
select set_config('test.second_cat',id::text,true)
  from public.cats where name='第二只';
insert into public.family_members(user_id,family_id)
  select '51000000-0000-0000-0000-000000000002',family_id
  from public.family_members where user_id='51000000-0000-0000-0000-000000000001';
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"51000000-0000-0000-0000-000000000002"}',true);
select public.bootstrap_identity();
select is((public.feed_cat(current_setting('test.first_cat')::uuid)->>'outcome'),
  'fed','other household member may pay 15');
select is((public.bootstrap_identity()->>'miao_coins')::int,15,
  'payer wallet lost exactly 15');
select is((public.feed_cat(current_setting('test.first_cat')::uuid)->>'outcome'),
  'already_fed','same payer retry does not charge twice');
select is((public.bootstrap_identity()->>'miao_coins')::int,15,
  'retry retains balance');
select is((select (c->>'fed_today')::boolean from jsonb_array_elements(
  public.cats_state()->'cats') c where c->>'name'='第一只'),true,
  'first cat is marked fed today');
reset role;
update public.wallets set miao_coins=14
  where owner_id='51000000-0000-0000-0000-000000000002';
set local role authenticated;
select throws_ok($$select public.feed_cat(current_setting('test.second_cat')::uuid)$$,
  '22023','Insufficient miao coins','payer cannot overdraft for active feeding');
select is((select (c->>'fed_today')::boolean from jsonb_array_elements(
  public.cats_state()->'cats') c where c->>'name'='第二只'),false,
  'failed payment creates no feeding');
select set_config('request.jwt.claims',
  '{"sub":"51000000-0000-0000-0000-000000000001"}',true);
select is((public.feed_cat(current_setting('test.first_cat')::uuid)->>'outcome'),
  'already_fed','other member cannot pay again');
select is((public.bootstrap_identity()->>'miao_coins')::int,30,
  'original owner not charged');
select is((public.feed_cat(current_setting('test.second_cat')::uuid)->>'outcome'),
  'fed','owner may feed second cat independently');
reset role;
select is((select count(*)::int from public.wallet_entries where kind='feeding'
  and owner_id in ('51000000-0000-0000-0000-000000000001',
    '51000000-0000-0000-0000-000000000002')),2,
  'one wallet ledger entry per paid cat');
select is((select business_day from public.cat_feedings limit 1),
  (clock_timestamp() at time zone 'Asia/Shanghai')::date,
  'feeding uses Beijing business date');
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"51000000-0000-0000-0000-000000000003"}',true);
select throws_ok($$select public.feed_cat(current_setting('test.second_cat')::uuid)$$,
  '42501','Cat is outside your family','outsider cannot feed family cat');
reset role;
select ok(not has_table_privilege('authenticated','public.cat_feedings','INSERT'),
  'client cannot forge feeding row');
select * from finish();
rollback;
