begin;
select no_plan();
insert into auth.users(id) values('60000000-0000-0000-0000-000000000001');
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"60000000-0000-0000-0000-000000000001"}',true);
select public.bootstrap_identity();
select public.create_family();
reset role;
insert into public.repair_episodes(id,family_id,status)
  select '60000000-0000-0000-0000-000000000010',family_id,'active'
  from public.family_members where user_id='60000000-0000-0000-0000-000000000001';
insert into public.repair_windows(id,episode_id,cycle_no,starts_at,ends_at,status)
  values('60000000-0000-0000-0000-000000000011',
    '60000000-0000-0000-0000-000000000010',1,
    now()-interval '3 hours',now()+interval '69 hours','active');
insert into public.study_sessions(id,owner_id,started_at,recorded_until,confirmed)
  select '60000000-0000-0000-0000-000000000012',
    '60000000-0000-0000-0000-000000000001',
    starts_at+interval '1 hour',starts_at+interval '2 hours',true
  from public.repair_windows where id='60000000-0000-0000-0000-000000000011';
select throws_ok($$insert into public.task_sessions
  (id,owner_id,activity,started_at,recorded_until,confirmed)
  select '60000000-0000-0000-0000-000000000013',
    '60000000-0000-0000-0000-000000000001','language',
    starts_at+interval '1 hour 30 minutes',starts_at+interval '2 hours 30 minutes',false
  from public.repair_windows where id='60000000-0000-0000-0000-000000000011'$$,
  '22023','Overlapping study interval',
  'existing cross-activity guard rejects duplicate personal repair time');
select is(public.repair_window_progress('60000000-0000-0000-0000-000000000011'),
  3600000::bigint,'rejected timer adds no repair progress');
select * from finish();
rollback;
