begin;
select no_plan();
insert into auth.users(id) values('55000000-0000-0000-0000-000000000001');
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"55000000-0000-0000-0000-000000000001"}',true);
select public.bootstrap_identity();
select public.create_family();
reset role;
insert into auth.users(id) values('55000000-0000-0000-0000-000000000002');
insert into public.family_members(user_id,family_id)
  select '55000000-0000-0000-0000-000000000002',family_id
  from public.family_members where user_id='55000000-0000-0000-0000-000000000001';
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"55000000-0000-0000-0000-000000000002"}',true);
select public.bootstrap_identity();
reset role;
insert into public.repair_episodes(id,family_id,triggered_at,status)
  select '55000000-0000-0000-0000-000000000010',family_id,
    '2026-09-01 00:00Z','active' from public.family_members
  where user_id='55000000-0000-0000-0000-000000000001';
insert into public.repair_windows
  (episode_id,cycle_no,starts_at,ends_at,status)
  values('55000000-0000-0000-0000-000000000010',1,
    '2026-09-01 00:00Z','2026-09-04 00:00Z','active');
insert into public.study_sessions(id,owner_id,started_at,recorded_until,confirmed)
  values('55000000-0000-0000-0000-000000000011',
    '55000000-0000-0000-0000-000000000001',
    '2026-09-01 00:00Z','2026-09-01 00:30Z',true);
insert into public.task_sessions
  (id,owner_id,activity,started_at,recorded_until,photo_path,confirmed)
  values('55000000-0000-0000-0000-000000000012',
    '55000000-0000-0000-0000-000000000001','language',
    '2026-09-01 00:30Z','2026-09-01 00:50Z','test/repair',true);
select is(public.rewardable_ms('55000000-0000-0000-0000-000000000001',
  '2026-09-01 00:00Z','2026-09-01 00:00Z','2026-09-01 00:30Z'),0::bigint,
  '30 minutes inside repair earn no coins');
select public.settle_study_for_owner('55000000-0000-0000-0000-000000000001',
  '2026-09-02 00:00Z');
select public.settle_tasks_for_owner('55000000-0000-0000-0000-000000000001');
select is((select miao_coins from public.wallets where owner_id=
  '55000000-0000-0000-0000-000000000001'),30,
  'study during repair did not increase wallet');
select is((select eagle_pounds from public.wallets where owner_id=
  '55000000-0000-0000-0000-000000000001'),0,
  'confirmed photo task during repair earned no special currency');

update public.repair_episodes set status='completed',
  completed_at='2026-09-01 01:00Z',grace_through='2026-09-02'
  where id='55000000-0000-0000-0000-000000000010';
update public.repair_windows set status='completed'
  where episode_id='55000000-0000-0000-0000-000000000010';
insert into public.task_sessions
  (id,owner_id,activity,started_at,recorded_until,photo_path,confirmed)
  values('55000000-0000-0000-0000-000000000015',
    '55000000-0000-0000-0000-000000000002','language',
    '2026-09-01 00:55Z','2026-09-01 01:15Z','test/repair-tail',true);
select public.settle_tasks_for_owner('55000000-0000-0000-0000-000000000002');
select is((select eagle_pounds from public.wallets where owner_id=
  '55000000-0000-0000-0000-000000000002'),0,
  'confirmed photo task crossing completion stays repair-only');
insert into public.study_sessions(id,owner_id,started_at,recorded_until,confirmed)
  values('55000000-0000-0000-0000-000000000014',
    '55000000-0000-0000-0000-000000000001',
    '2026-09-01 00:50Z','2026-09-01 01:05Z',true);
select is(public.rewardable_ms('55000000-0000-0000-0000-000000000001',
  '2026-09-01 00:50Z','2026-09-01 01:00Z','2026-09-01 01:05Z'),
  0::bigint,'same timer stays repair-only after the two-hour target');
select public.settle_study_for_owner('55000000-0000-0000-0000-000000000001',
  '2026-09-02 00:00Z');
select is((select miao_coins from public.wallets where owner_id=
  '55000000-0000-0000-0000-000000000001'),30,
  'settlement does not pay the tail of the same study timer');
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"55000000-0000-0000-0000-000000000001"}',true);
select is((public.sync_study_run_session(
  '55000000-0000-0000-0000-000000000016',
  '2026-09-01 01:05Z','2026-09-01 01:10Z',true,
  '55000000-0000-0000-0000-000000000014')->'wallet'->>'miao_coins')::int,
  30,'paused and resumed segment of the same timer also earns nothing');
reset role;
select is((select run_id from public.study_sessions where id=
  '55000000-0000-0000-0000-000000000016'),
  '55000000-0000-0000-0000-000000000014'::uuid,
  'cloud stores the logical timer ID across pause and resume');
insert into public.study_sessions(id,owner_id,started_at,recorded_until,confirmed)
  values('55000000-0000-0000-0000-000000000013',
    '55000000-0000-0000-0000-000000000001',
    '2026-09-01 01:10Z','2026-09-01 01:15Z',true);
select public.settle_study_for_owner('55000000-0000-0000-0000-000000000001',
  '2026-09-02 00:00Z');
select is((select miao_coins from public.wallets where owner_id=
  '55000000-0000-0000-0000-000000000001'),40,
  'new five-minute session after repair completion earns ten');
select is(public.rewardable_ms('55000000-0000-0000-0000-000000000001',
  '2026-08-31 23:55Z','2026-08-31 23:55Z','2026-09-01 00:05Z'),
  300000::bigint,
  'straddling interval only counts pre-repair five minutes');
select * from finish();
rollback;
