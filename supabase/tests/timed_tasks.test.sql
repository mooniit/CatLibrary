begin;
select no_plan();
insert into auth.users(id) values ('85000000-0000-0000-0000-000000000001');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"85000000-0000-0000-0000-000000000001"}',true);
select public.bootstrap_identity();
select public.create_family();
reset role;
insert into public.repair_episodes(id,family_id,triggered_at,status)
  select '85000000-0000-0000-0000-000000000010',family_id,'2026-09-01 00:00Z','active'
  from public.family_members where user_id='85000000-0000-0000-0000-000000000001';
insert into public.repair_windows(episode_id,cycle_no,starts_at,ends_at,status)
  values('85000000-0000-0000-0000-000000000010',1,'2026-09-01 00:00Z','2026-09-04 00:00Z','active');
update public.repair_episodes set status='completed',completed_at='2026-09-01 00:30Z',grace_through='2026-09-02'
  where id='85000000-0000-0000-0000-000000000010';
update public.repair_windows set status='completed' where episode_id='85000000-0000-0000-0000-000000000010';
set local role authenticated;
select is((public.sync_timed_task_session('85000000-0000-0000-0000-000000000011','language',
  '2026-09-01 00:10Z','2026-09-01 00:20Z',true,'85000000-0000-0000-0000-000000000011','2026-09-01 00:10Z',false)
  ->'wallet'->>'eagle_pounds')::int,0,'photo-free task inside repair earns no currency');
select is((public.sync_timed_task_session('85000000-0000-0000-0000-000000000012','language',
  '2026-09-01 00:40Z','2026-09-01 00:50Z',true,'85000000-0000-0000-0000-000000000011','2026-09-01 00:10Z',false)
  ->'wallet'->>'eagle_pounds')::int,0,'resumed segment stays repair-only after completion');
select is((public.sync_timed_task_session('85000000-0000-0000-0000-000000000013','exercise',
  '2026-09-01 00:55Z','2026-09-01 01:15Z',true,'85000000-0000-0000-0000-000000000013','2026-09-01 00:55Z',false)
  ->'wallet'->>'gems')::int,4,'new timer after repair resumes normal rewards');
select throws_ok($$select public.sync_timed_task_session('85000000-0000-0000-0000-000000000014','exercise',
  '2026-09-01 01:00Z','2026-09-01 01:20Z',true,'85000000-0000-0000-0000-000000000014','2026-09-01 01:00Z',false)$$,
  '22023','Overlapping task interval','overlap remains rejected');
select throws_ok($$update public.task_timer_runs set started_at=started_at+interval '1 minute'$$,
  '42501',null,'authenticated clients cannot rewrite a run directly');
select throws_ok($$select public.sync_timed_task_session('85000000-0000-0000-0000-000000000015','exercise',
  '2026-09-01 01:20Z','2026-09-01 01:30Z',true,'85000000-0000-0000-0000-000000000011','2026-09-01 00:10Z',false)$$,
  '42501','Timer identity mismatch','same run cannot change activity');
select * from finish();
rollback;
