begin;
select no_plan();
insert into auth.users(id) values
  ('53000000-0000-0000-0000-000000000001'),
  ('53000000-0000-0000-0000-000000000002'),
  ('53000000-0000-0000-0000-000000000003');
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"53000000-0000-0000-0000-000000000001"}',true);
select public.bootstrap_identity();
select public.create_family();
select public.adopt_cat('black_short','甲猫一');
select public.adopt_cat('light_long','甲猫二');
reset role;
insert into public.family_members(user_id,family_id)
  select '53000000-0000-0000-0000-000000000002',family_id
  from public.family_members where user_id='53000000-0000-0000-0000-000000000001';
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"53000000-0000-0000-0000-000000000002"}',true);
select public.bootstrap_identity();
select public.adopt_cat('black_short','乙猫');
reset role;
select set_config('test.home',family_id::text,true) from public.family_members
  where user_id='53000000-0000-0000-0000-000000000001';
update public.cats set adopted_at='2026-08-31 16:00Z'
  where family_id=current_setting('test.home')::uuid;
update public.wallets set miao_coins=case
  when owner_id='53000000-0000-0000-0000-000000000001' then -130 else 0 end
  where owner_id in ('53000000-0000-0000-0000-000000000001',
    '53000000-0000-0000-0000-000000000002');

select public.settle_family_day(current_setting('test.home')::uuid,'2026-09-01');
select is((select miao_coins from public.wallets
  where owner_id='53000000-0000-0000-0000-000000000001'),-150,
  'A newly reaches debt cap');
select is((select count(*)::int from public.daily_cat_charges d
  where d.business_day='2026-09-01' and d.owner_id=
    '53000000-0000-0000-0000-000000000001' and d.status='proxy'),0,
  'newly capped owner never triggers same-day proxy');
select is((select miao_coins from public.wallets
  where owner_id='53000000-0000-0000-0000-000000000002'),-20,
  'B pays own cat fee only on A cap day');

select public.settle_family_day(current_setting('test.home')::uuid,'2026-09-02');
select is((select miao_coins from public.wallets
  where owner_id='53000000-0000-0000-0000-000000000001'),-150,
  'A old debt is not transferred');
select is((select miao_coins from public.wallets
  where owner_id='53000000-0000-0000-0000-000000000002'),-82,
  'B pays own interest and cat before two 20-coin proxy fees');
select is((select count(*)::int from public.daily_cat_charges d
  where d.business_day='2026-09-02' and d.owner_id=
    '53000000-0000-0000-0000-000000000001' and d.status='proxy'
    and d.payer_id='53000000-0000-0000-0000-000000000002' and d.paid=20),2,
  'each current cat fee has its own bounded proxy record');
select is((select total_paid from public.proxy_payment_notices
  where payer_id='53000000-0000-0000-0000-000000000002'
    and business_day='2026-09-02'),40,
  'payer receives one daily summary of both proxy charges');
select public.settle_family_day(current_setting('test.home')::uuid,'2026-09-02');
select is((select miao_coins from public.wallets
  where owner_id='53000000-0000-0000-0000-000000000002'),-82,
  'retry never repeats proxy charges');
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"53000000-0000-0000-0000-000000000002"}',true);
select is((public.proxy_notice_state()->0->>'paid')::int,40,
  'payer sees pending notice');
select public.ack_proxy_notice('2026-09-02');
select is(jsonb_array_length(public.proxy_notice_state()),0,
  'acknowledged notice is not shown again');
select set_config('request.jwt.claims',
  '{"sub":"53000000-0000-0000-0000-000000000003"}',true);
select is(jsonb_array_length(public.proxy_notice_state()),0,
  'outsider cannot read household payment notice');
reset role;
select ok(not has_table_privilege('authenticated','public.proxy_payment_notices','INSERT'),
  'client cannot forge proxy notice');
select * from finish();
rollback;
