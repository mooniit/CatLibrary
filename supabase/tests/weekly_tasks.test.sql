begin;
select no_plan();
insert into auth.users(id) values
  ('50000000-0000-0000-0000-000000000001'),
  ('50000000-0000-0000-0000-000000000002'),
  ('50000000-0000-0000-0000-000000000003'),
  ('50000000-0000-0000-0000-000000000004'),
  ('50000000-0000-0000-0000-000000000005');
insert into public.families(id,creator_id) values
  ('51000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000001');
insert into public.family_members(user_id,family_id) values
  ('50000000-0000-0000-0000-000000000001','51000000-0000-0000-0000-000000000001'),
  ('50000000-0000-0000-0000-000000000002','51000000-0000-0000-0000-000000000001');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"50000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select public.bootstrap_identity();
select set_config('request.jwt.claims','{"sub":"50000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select public.bootstrap_identity();
select set_config('request.jwt.claims','{"sub":"50000000-0000-0000-0000-000000000003","role":"authenticated"}',true);
select public.bootstrap_identity();
select set_config('request.jwt.claims','{"sub":"50000000-0000-0000-0000-000000000004","role":"authenticated"}',true);
select public.bootstrap_identity();
select set_config('request.jwt.claims','{"sub":"50000000-0000-0000-0000-000000000005","role":"authenticated"}',true);
select public.bootstrap_identity();
reset role;
select is((select count(*)::int from public.weekly_task_catalog),15,'catalog has exactly 15 selected tasks');
select is((select count(distinct id)::int from public.weekly_task_catalog),15,'catalog IDs are stable and unique');
select is((select count(*)::int from public.weekly_task_catalog
  where evidence_kind='screenshot' and image_count=1),3,'three language tasks require one screenshot each');
select is((select image_count::int from public.weekly_task_catalog where id='12'),2,'sky task requires two photos');
insert into public.weekly_task_offers(id,owner_id,batch_id,week_start,cycle_no,slot,task_id) values
  ('52000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000001',
    '53000000-0000-0000-0000-000000000001',
    (now() at time zone 'Asia/Shanghai')::date-(extract(isodow from now() at time zone 'Asia/Shanghai')::int-1),1,0,'1'),
  ('52000000-0000-0000-0000-000000000002','50000000-0000-0000-0000-000000000001',
    '53000000-0000-0000-0000-000000000001',
    (now() at time zone 'Asia/Shanghai')::date-(extract(isodow from now() at time zone 'Asia/Shanghai')::int-1),1,1,'12'),
  ('52000000-0000-0000-0000-000000000003','50000000-0000-0000-0000-000000000002',
    '53000000-0000-0000-0000-000000000002',
    (now() at time zone 'Asia/Shanghai')::date-(extract(isodow from now() at time zone 'Asia/Shanghai')::int-1),1,0,'L1');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"50000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select is(jsonb_array_length(public.weekly_my_tasks()),2,'member sees only own assigned two tasks');
select throws_ok($$select public.weekly_confirm('52000000-0000-0000-0000-000000000003',now())$$,
  '42501','Weekly task not assigned to this user','cannot take another member reward');
select throws_ok($$select public.weekly_confirm('52000000-0000-0000-0000-000000000001',now())$$,
  '22023','Text evidence required','text task cannot confirm empty');
select public.weekly_save_draft('52000000-0000-0000-0000-000000000001','一个让我改变想法的观点');
select is((public.weekly_confirm('52000000-0000-0000-0000-000000000001',now())->'wallet'->>'gems')::int,
  6,'text confirmation grants six gems');
select is((public.weekly_confirm('52000000-0000-0000-0000-000000000001',now())->'wallet'->>'eagle_pounds')::int,
  6,'retry returns existing six eagle pounds');
select is((select count(*)::int from public.wallet_entries where kind='weekly'
  and owner_id=auth.uid()),1,'one confirmation has one dual-currency ledger entry');
select public.weekly_save_draft('52000000-0000-0000-0000-000000000002',null);
select throws_ok($$select public.weekly_confirm('52000000-0000-0000-0000-000000000002',now())$$,
  '22023','Required photo missing','two-photo task cannot confirm without photos');
reset role;
insert into storage.objects(bucket_id,name) values
  ('weekly-photos','50000000-0000-0000-0000-000000000001/52000000-0000-0000-0000-000000000002/0');
set local role authenticated;
select throws_ok($$select public.weekly_confirm('52000000-0000-0000-0000-000000000002',now())$$,
  '22023','Required photo missing','one of two photos is insufficient');
reset role;
insert into storage.objects(bucket_id,name) values
  ('weekly-photos','50000000-0000-0000-0000-000000000001/52000000-0000-0000-0000-000000000002/1');
set local role authenticated;
select is((public.weekly_confirm('52000000-0000-0000-0000-000000000002',now())->'wallet'->>'gems')::int,
  12,'two completed weekly tasks total twelve gems');
select is((select eagle_pounds from public.wallets where owner_id=auth.uid()),12,
  'two completed weekly tasks total twelve eagle pounds');
select is((select count(*)::int from storage.objects where bucket_id='weekly-photos'),2,
  'owner can read both private photos');
select set_config('request.jwt.claims','{"sub":"50000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select is((select count(*)::int from storage.objects where bucket_id='weekly-photos'),2,
  'family member may read confirmed weekly photos');
select is(jsonb_array_length(public.weekly_family_feed()),2,
  'family member may read confirmed text and photo records');
select is(jsonb_array_length(public.weekly_my_tasks()),1,
  'family member has separate personal assignment');
select set_config('request.jwt.claims','{"sub":"50000000-0000-0000-0000-000000000003","role":"authenticated"}',true);
select is((select count(*)::int from storage.objects where bucket_id='weekly-photos'),0,
  'outsider cannot read weekly photos');
select is(jsonb_array_length(public.weekly_family_feed()),0,
  'outsider cannot read weekly notes');
reset role;
with w as (select (now() at time zone 'Asia/Shanghai')::date
  -(extract(isodow from now() at time zone 'Asia/Shanghai')::int-1)-7 as monday)
insert into public.weekly_task_offers
  (id,owner_id,batch_id,week_start,cycle_no,slot,task_id,published_at)
select '52000000-0000-0000-0000-000000000004',
  '50000000-0000-0000-0000-000000000003',
  '53000000-0000-0000-0000-000000000003',monday,1,0,'3',
  monday::timestamp at time zone 'Asia/Shanghai' from w;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"50000000-0000-0000-0000-000000000003","role":"authenticated"}',true);
select throws_ok($$select public.weekly_confirm('52000000-0000-0000-0000-000000000004',now())$$,
  '22023','Confirmation time outside assigned week','late online tap cannot backdate itself');
select is((public.weekly_confirm('52000000-0000-0000-0000-000000000004',
  ((now() at time zone 'Asia/Shanghai')::date
    -(extract(isodow from now() at time zone 'Asia/Shanghai')::int))::timestamp
      at time zone 'Asia/Shanghai')
  ->'wallet'->>'gems')::int,6,'offline Sunday confirmation settles after Monday refresh');
select is((select count(*)::int from public.wallet_entries where owner_id=auth.uid()
  and kind='weekly'),1,'late sync still writes one reward ledger entry');
reset role;
do $$
declare n integer;
begin
  for n in 0..14 loop
    perform public.weekly_ensure_personal('50000000-0000-0000-0000-000000000004',
      '2026-09-28 00:00Z'::timestamptz+n*interval '7 days');
  end loop;
  perform public.weekly_ensure_personal('50000000-0000-0000-0000-000000000004',
    '2026-09-28 00:00Z');
end;
$$;
select is((select count(*)::int from public.weekly_task_offers
  where owner_id='50000000-0000-0000-0000-000000000004'),30,
  'fifteen weeks produce exactly two personal offers per week');
select is((select count(distinct task_id)::int from public.weekly_task_offers
  where owner_id='50000000-0000-0000-0000-000000000004' and cycle_no=1),15,
  'first fifteen-task cycle uses every task once');
select is((select count(*)::int from public.weekly_task_offers
  where owner_id='50000000-0000-0000-0000-000000000004' and cycle_no=2),15,
  'second cycle also has fifteen draws after fifteen weeks');
select is((select count(distinct task_id)::int from public.weekly_task_offers
  where owner_id='50000000-0000-0000-0000-000000000004'
    and week_start='2026-11-16'),2,
  'odd-pool boundary week has two different tasks');
select is((select count(*)::int from public.weekly_task_offers
  where owner_id='50000000-0000-0000-0000-000000000004'
    and week_start='2026-11-16' and cycle_no=1),1,
  'odd-pool boundary draws last old-cycle task first');
insert into public.weekly_task_catalog(id,prompt,evidence_kind,image_count)
  select 'T'||n,'Test task '||n,'self',0 from generate_series(1,15) n;
do $$
declare n integer;
begin
  for n in 0..14 loop
    perform public.weekly_ensure_personal('50000000-0000-0000-0000-000000000005',
      '2026-09-28 00:00Z'::timestamptz+n*interval '7 days');
  end loop;
end;
$$;
select is((select count(distinct task_id)::int from public.weekly_task_offers
  where owner_id='50000000-0000-0000-0000-000000000005' and cycle_no=1),30,
  'a future thirty-task catalog uses all tasks across fifteen weeks');
select * from finish();
rollback;
