begin;
select no_plan();
insert into auth.users(id) values
 ('8a100000-0000-0000-0000-000000000001'),
 ('8a100000-0000-0000-0000-000000000002');
select set_config('request.jwt.claims','{"sub":"8a100000-0000-0000-0000-000000000001"}',true);
select public.bootstrap_identity();
select public.create_family();
insert into public.family_members(user_id,family_id)
 select '8a100000-0000-0000-0000-000000000002',family_id
 from public.family_members where user_id='8a100000-0000-0000-0000-000000000001';
select set_config('request.jwt.claims','{"sub":"8a100000-0000-0000-0000-000000000002"}',true);
select public.bootstrap_identity();
insert into public.cats(id,family_id,owner_id,appearance,name)
 select '8a100000-0000-0000-0000-000000000011',family_id,user_id,'black_short','橘点'
 from public.family_members where user_id='8a100000-0000-0000-0000-000000000001';
insert into public.cats(id,family_id,owner_id,appearance,name)
 select '8a100000-0000-0000-0000-000000000012',family_id,user_id,'light_long','白云'
 from public.family_members where user_id='8a100000-0000-0000-0000-000000000001';
insert into public.cats(id,family_id,owner_id,appearance,name)
 select '8a100000-0000-0000-0000-000000000013',family_id,user_id,'black_short','另一成员的猫'
 from public.family_members where user_id='8a100000-0000-0000-0000-000000000002';
select set_config('request.jwt.claims','{"sub":"8a100000-0000-0000-0000-000000000001"}',true);

select is(public.feeding_reminder_at('2099-10-09 12:59:59Z')->>'status','before_time',
 '20:59:59 Beijing does not create a reminder');
select is((select count(*) from public.feeding_reminders
  where owner_id='8a100000-0000-0000-0000-000000000001'),0::bigint,
 'early read does not consume the daily reminder');
select is(public.feeding_reminder_at('2099-10-09 13:00Z')->>'status','ready',
 '21:00 Beijing makes one aggregate reminder');
select is(jsonb_array_length(public.feeding_reminder_at('2099-10-09 13:00Z')->'cats'),2,
 'only the two cats registered to this owner appear');
select is((select count(*) from public.feeding_reminders
  where owner_id='8a100000-0000-0000-0000-000000000001'),1::bigint,
 'repeated requests and a lost receipt reuse one daily record');
select is(public.feeding_reminder_at('2099-10-09 15:59:59Z')->>'business_day','2099-10-09',
 'the reminder stays on the Beijing business date');

insert into public.cat_feedings(cat_id,business_day,payer_id) values
 ('8a100000-0000-0000-0000-000000000011','2099-10-09','8a100000-0000-0000-0000-000000000002');
select is(jsonb_array_length(public.feeding_reminder_at('2099-10-09 14:00Z')->'cats'),1,
 'partner feeding immediately removes that cat from the reminder');
select is(public.feeding_reminder_at('2099-10-09 14:00Z')->'cats'->0->>'name','白云',
 'remaining aggregate names are accurate');
select is(public.ack_feeding_reminder('2099-10-09','in_app')->>'status','acknowledged',
 'owner acknowledges the application reminder');
select is(public.ack_feeding_reminder('2099-10-09','in_app')->>'status','acknowledged',
 'acknowledgment retry is idempotent');
select ok((public.feeding_reminder_at('2099-10-09 14:00Z')->>'in_app_seen')::boolean,
 'application delivery state survives another read');
select ok(not (public.feeding_reminder_at('2099-10-09 14:00Z')->>'notification_seen')::boolean,
 'application acknowledgment does not claim system notification delivery');
select is(public.ack_feeding_reminder('2099-10-09','notification')->>'status','acknowledged',
 'notification acknowledgment is independent');
select throws_ok($$select public.ack_feeding_reminder('2099-10-09','email')$$,
 '22023','Invalid reminder acknowledgment','unsupported notification channel is rejected');

select set_config('request.jwt.claims','{"sub":"8a100000-0000-0000-0000-000000000002"}',true);
select is(public.ack_feeding_reminder('2099-10-09','in_app')->>'status','not_found',
 'another member cannot acknowledge the owner record');
set local role authenticated;
select is((select count(*) from public.feeding_reminders),0::bigint,
 'RLS hides the other owner record');
select throws_ok($$select public.feeding_reminder_at('2099-10-09 13:00Z')$$,
 '42501','permission denied for function feeding_reminder_at',
 'client cannot inject a reminder time');
select throws_ok($$insert into public.feeding_reminders(owner_id,family_id,business_day,cats)
 values(auth.uid(),'8a100000-0000-0000-0000-000000000099','2099-10-09','[]')$$,
 '42501','permission denied for table feeding_reminders','client cannot forge reminder records');
reset role;

select set_config('request.jwt.claims','{"sub":"8a100000-0000-0000-0000-000000000001"}',true);
insert into public.cat_feedings(cat_id,business_day,payer_id) values
 ('8a100000-0000-0000-0000-000000000012','2099-10-09','8a100000-0000-0000-0000-000000000001');
select is(public.feeding_reminder_at('2099-10-09 14:00Z')->>'status','empty',
 'all fed hides the earlier reminder');
select is(public.feeding_reminder_at('2099-10-09 16:00Z')->>'status','before_time',
 'midnight does not redisplay yesterday reminder');
select is(public.feeding_reminder_at('2099-10-10 13:00Z')->>'status','ready',
 'new Beijing day has its own reminder');

-- A trip that returned earlier today still exempts that business day from fees.
insert into public.cat_trips(id,family_id,cat_id,arranged_by,destination,started_at,ends_at,returned_at)
 select '8a100000-0000-0000-0000-000000000020',family_id,
 '8a100000-0000-0000-0000-000000000012',user_id,'palace',
 '2099-10-09 03:00Z','2099-10-10 03:00Z','2099-10-10 03:01Z'
 from public.family_members where user_id='8a100000-0000-0000-0000-000000000001';
select is(jsonb_array_length(public.feeding_reminder_at('2099-10-10 13:00Z')->'cats'),1,
 'returned travel cat remains exempt for the day, so no feeding-fee reminder');

insert into public.repair_episodes(id,family_id,status)
 select '8a100000-0000-0000-0000-000000000030',family_id,'active'
 from public.family_members where user_id='8a100000-0000-0000-0000-000000000001';
select is(public.feeding_reminder_at('2099-10-10 13:00Z')->>'status','empty',
 'repair suppresses even a previously created reminder');
update public.repair_episodes set status='completed',completed_at='2099-10-10 14:00Z',
 grace_through='2099-10-11' where id='8a100000-0000-0000-0000-000000000030';
select is(public.feeding_reminder_at('2099-10-11 13:00Z')->>'status','empty',
 'repair grace does not warn about a waived fee');
select is(public.feeding_reminder_at('2099-10-12 13:00Z')->>'status','ready',
 'reminders resume after the grace period');
select is((select miao_coins from public.wallets where owner_id='8a100000-0000-0000-0000-000000000001'),30,
 'reminder reads and acknowledgments never change the wallet');
select is((select count(*) from public.wallet_entries where owner_id='8a100000-0000-0000-0000-000000000001'),1::bigint,
 'no fee or reward ledger rows were added');
select set_config('request.jwt.claims','{}',true);
select throws_ok($$select public.get_feeding_reminder()$$,'42501','Authentication required',
 'reminder API requires an authenticated identity');
select * from finish();
rollback;
