begin;
select no_plan();
insert into auth.users(id) values
  ('67000000-0000-0000-0000-000000000001'),
  ('67000000-0000-0000-0000-000000000002');
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"67000000-0000-0000-0000-000000000001"}',true);
select public.bootstrap_identity();
select public.create_family();
select public.adopt_cat('black_short','早领养');
select public.adopt_cat('light_long','晚领养');
reset role;
insert into public.family_members(user_id,family_id)
  select '67000000-0000-0000-0000-000000000002',family_id
  from public.family_members where user_id='67000000-0000-0000-0000-000000000001';
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"67000000-0000-0000-0000-000000000002"}',true);
select public.bootstrap_identity();
reset role;
update public.cats set adopted_at=case when name='早领养'
  then '2026-09-01 00:00Z'::timestamptz
  else '2026-09-01 00:01Z'::timestamptz end
  where owner_id='67000000-0000-0000-0000-000000000001';
update public.wallets set miao_coins=-150 where owner_id in
  ('67000000-0000-0000-0000-000000000001',
   '67000000-0000-0000-0000-000000000002');
insert into public.study_sessions(id,owner_id,started_at,recorded_until,confirmed)
  values('67000000-0000-0000-0000-000000000010',
    '67000000-0000-0000-0000-000000000002',
    '2026-09-01 01:00Z','2026-09-01 01:10Z',true);
select is(public.settle_family_day((select family_id from public.family_members
  where user_id='67000000-0000-0000-0000-000000000001'),
  '2026-09-01')->>'mode','normal',
  'reward first moves B off -150, so dual repair does not start');
select is((select count(*)::int from public.repair_episodes),0,
  'no repair episode is opened after B reward offsets debt');
select is((select balance_after_reward from public.daily_interest_charges
  where owner_id='67000000-0000-0000-0000-000000000002'),-130,
  'interest uses B balance after the 20-coin reward');
select results_eq($$select name,paid from public.daily_cat_charges d
  join public.cats c on c.id=d.cat_id
  where d.owner_id='67000000-0000-0000-0000-000000000001'
  order by c.adopted_at,c.id$$,
  $$values ('早领养'::text,7),('晚领养'::text,0)$$,
  'remaining proxy capacity pays the earlier adopted cat first');
select * from finish();
rollback;
