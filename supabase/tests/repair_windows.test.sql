begin;
select no_plan();
insert into auth.users(id) values
  ('56000000-0000-0000-0000-000000000001'),
  ('56000000-0000-0000-0000-000000000002');
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"56000000-0000-0000-0000-000000000001"}',true);
select public.bootstrap_identity();
select public.create_family();
reset role;
insert into public.family_members(user_id,family_id)
  select '56000000-0000-0000-0000-000000000002',family_id
  from public.family_members where user_id='56000000-0000-0000-0000-000000000001';
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"56000000-0000-0000-0000-000000000002"}',true);
select public.bootstrap_identity();
reset role;
insert into public.repair_episodes(id,family_id,status)
  select '56000000-0000-0000-0000-000000000010',family_id,'active'
  from public.family_members where user_id='56000000-0000-0000-0000-000000000001';
insert into public.repair_windows
  (id,episode_id,cycle_no,starts_at,ends_at,status)
  select '56000000-0000-0000-0000-000000000011',
    '56000000-0000-0000-0000-000000000010',1,
    started,started+interval '72 hours','active'
  from (select clock_timestamp()-interval '150 hours' as started) time_anchor;
insert into public.study_sessions(id,owner_id,started_at,recorded_until,confirmed)
  select '56000000-0000-0000-0000-000000000012',
    '56000000-0000-0000-0000-000000000001',
    starts_at+interval '1 hour',starts_at+interval '1 hour 30 minutes',true
  from public.repair_windows where cycle_no=1;
insert into public.task_sessions
  (id,owner_id,activity,started_at,recorded_until,confirmed)
  select '56000000-0000-0000-0000-000000000013',
    '56000000-0000-0000-0000-000000000002','exercise',
    starts_at+interval '2 hours',starts_at+interval '2 hours 20 minutes',false
  from public.repair_windows where cycle_no=1;
select is(public.repair_window_progress(
  '56000000-0000-0000-0000-000000000011'),3000000::bigint,
  'two members contribute 30+20 minutes in one window; photo pending still counts');
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"56000000-0000-0000-0000-000000000001"}',true);
select is((public.repair_state()->>'cycle_no')::int,3,
  'two expired 72-hour windows reopen the third');
reset role;
select results_eq($$select cycle_no,status from public.repair_windows
  where episode_id='56000000-0000-0000-0000-000000000010'
  order by cycle_no$$,
  $$values (1,'failed'::text),(2,'failed'::text),(3,'active'::text)$$,
  'earlier windows retain their own progress and current window starts fresh');
select is((select progress_ms from public.repair_windows where cycle_no=1
  and episode_id='56000000-0000-0000-0000-000000000010'),3000000::bigint,
  'expired window keeps its 50-minute audit record');

insert into public.study_sessions(id,owner_id,started_at,recorded_until,confirmed)
  select '56000000-0000-0000-0000-000000000014',
    '56000000-0000-0000-0000-000000000001',
    starts_at+interval '1 hour',starts_at+interval '2 hours',true
  from public.repair_windows where cycle_no=3;
insert into public.task_sessions
  (id,owner_id,activity,started_at,recorded_until,confirmed)
  select '56000000-0000-0000-0000-000000000015',
    '56000000-0000-0000-0000-000000000002','language',
    starts_at+interval '2 hours',starts_at+interval '3 hours',false
  from public.repair_windows where cycle_no=3;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"56000000-0000-0000-0000-000000000002"}',true);
select is(public.repair_state()->>'status','completed',
  'two members reach two-hour target together');
reset role;
select is((select status from public.repair_windows where cycle_no=3
  and episode_id='56000000-0000-0000-0000-000000000010'),'completed',
  'successful window is durable');
select is((select grace_through from public.repair_episodes where id=
  '56000000-0000-0000-0000-000000000010'),
  (clock_timestamp() at time zone 'Asia/Shanghai')::date+1,
  'repair grants completion day and next day');

insert into auth.users(id) values('57000000-0000-0000-0000-000000000001');
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"57000000-0000-0000-0000-000000000001"}',true);
select public.bootstrap_identity();
select public.create_family();
reset role;
insert into public.repair_episodes(id,family_id,status)
  select '57000000-0000-0000-0000-000000000010',family_id,'active'
  from public.family_members where user_id='57000000-0000-0000-0000-000000000001';
insert into public.repair_windows
  (episode_id,cycle_no,starts_at,ends_at,status)
  select '57000000-0000-0000-0000-000000000010',1,
    started,started+interval '72 hours','active'
  from (select clock_timestamp()-interval '150 hours' as started) time_anchor;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"57000000-0000-0000-0000-000000000001"}',true);
select is((public.repair_state()->>'cycle_no')::int,3,
  'disconnected member resumes in third window');
reset role;
insert into public.study_sessions(id,owner_id,started_at,recorded_until,confirmed)
  select '57000000-0000-0000-0000-000000000011',
    '57000000-0000-0000-0000-000000000001',
    starts_at+interval '1 hour',starts_at+interval '3 hours',true
  from public.repair_windows
  where episode_id='57000000-0000-0000-0000-000000000010' and cycle_no=1;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"57000000-0000-0000-0000-000000000001"}',true);
select is((public.repair_state()->>'cycle_no')::int,1,
  'late two-hour upload is credited to its original first window');
reset role;
select is((select status from public.repair_windows
  where episode_id='57000000-0000-0000-0000-000000000010' and cycle_no=3),
  'superseded','later active window closes when earlier upload completes repair');

insert into auth.users(id) values('65000000-0000-0000-0000-000000000001');
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"65000000-0000-0000-0000-000000000001"}',true);
select public.bootstrap_identity();
select public.create_family();
reset role;
insert into public.repair_episodes(id,family_id,status)
  select '65000000-0000-0000-0000-000000000010',family_id,'active'
  from public.family_members where user_id='65000000-0000-0000-0000-000000000001';
insert into public.repair_windows(episode_id,cycle_no,starts_at,ends_at,status)
  values('65000000-0000-0000-0000-000000000010',1,
    now()-interval '73 hours',now()-interval '1 hour','active');
insert into public.study_sessions(id,owner_id,started_at,recorded_until,confirmed)
  select '65000000-0000-0000-0000-000000000011',
    '65000000-0000-0000-0000-000000000001',
    ends_at-interval '30 minutes',ends_at+interval '30 minutes',true
  from public.repair_windows where episode_id='65000000-0000-0000-0000-000000000010';
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"65000000-0000-0000-0000-000000000001"}',true);
select is((public.repair_state()->>'cycle_no')::int,2,
  'a study interval crossing exact 72-hour boundary opens second cycle');
reset role;
select results_eq($$select cycle_no,progress_ms from public.repair_windows
  where episode_id='65000000-0000-0000-0000-000000000010'
  order by cycle_no$$,
  $$values (1,1800000::bigint),(2,1800000::bigint)$$,
  'time on each side of exact window boundary is assigned once to that cycle');
select * from finish();
rollback;
