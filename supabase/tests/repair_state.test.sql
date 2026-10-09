begin;
select no_plan();
insert into auth.users(id) values
  ('54000000-0000-0000-0000-000000000001'),
  ('54000000-0000-0000-0000-000000000002');
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"54000000-0000-0000-0000-000000000001"}',true);
select public.bootstrap_identity();
select public.create_family();
select public.adopt_cat('black_short','修缮猫');
reset role;
select set_config('test.home',family_id::text,true) from public.family_members
  where user_id='54000000-0000-0000-0000-000000000001';
update public.cats set adopted_at='2026-08-31 16:00Z'
  where family_id=current_setting('test.home')::uuid;
select set_config('test.cat',(select id::text from public.cats
  where name='修缮猫'),true);
update public.wallets set miao_coins=-130
  where owner_id='54000000-0000-0000-0000-000000000001';
select public.settle_family_day(current_setting('test.home')::uuid,'2026-09-01');
select is((select status from public.repair_episodes
  where family_id=current_setting('test.home')::uuid),'pending',
  'single user reaching -150 triggers pending repair after fee');
select is((select count(*)::int from public.repair_windows w join public.repair_episodes e
  on e.id=w.episode_id where e.family_id=current_setting('test.home')::uuid),0,
  '72-hour clock has not started before user returns');
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"54000000-0000-0000-0000-000000000001"}',true);
select is(public.repair_state()->>'status','active',
  'first online read starts shared window');
select is(public.cats_state()->>'repairing','true',
  'cat page receives the active repair lock');
select throws_ok($$select public.adopt_cat('light_long','新猫')$$,
  '22023','Repair in progress','adoption is locked during repair');
select throws_ok($$select public.feed_cat(current_setting('test.cat')::uuid)$$,
  '22023','Repair in progress','feeding cannot charge during repair');
select is((public.repair_state()->>'cycle_no')::int,1,
  'repeated read stays in first window');
reset role;
select is((select count(*)::int from public.repair_windows w join public.repair_episodes e
  on e.id=w.episode_id where e.family_id=current_setting('test.home')::uuid),1,
  'repeated read cannot create another window');
select is((select w.ends_at-w.starts_at from public.repair_windows w join public.repair_episodes e
  on e.id=w.episode_id where e.family_id=current_setting('test.home')::uuid),
  interval '72 hours','window has full 72 hours');
select set_config('test.window',(select w.id::text from public.repair_windows w join public.repair_episodes e
  on e.id=w.episode_id where e.family_id=current_setting('test.home')::uuid),true);
insert into public.family_members(user_id,family_id)
  values('54000000-0000-0000-0000-000000000002',
    current_setting('test.home')::uuid);
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"54000000-0000-0000-0000-000000000002"}',true);
select public.bootstrap_identity();
select is(public.repair_state()->>'window_id',current_setting('test.window'),
  'second member joining later sees same window without reset');
reset role;
select * from finish();
rollback;
