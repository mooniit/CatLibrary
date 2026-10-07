begin;
select no_plan();
insert into auth.users(id) values
  ('40000000-0000-0000-0000-000000000001'),
  ('40000000-0000-0000-0000-000000000002');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"40000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select public.bootstrap_identity();
select public.sync_study_session('41000000-0000-0000-0000-000000000001',
  '2026-09-01 00:00Z','2026-09-01 01:00Z',true);
reset role;
update public.wallets set miao_coins=-20,eagle_pounds=1,gems=1
  where owner_id='40000000-0000-0000-0000-000000000001';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"40000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select is((public.exchange_special('42000000-0000-0000-0000-000000000001','eagle')
  ->'wallet'->>'miao_coins')::int,-15,'eagle exchange pays down debt by five');
select is((select eagle_pounds from public.wallets where owner_id=auth.uid()),0,
  'one eagle pound was spent');
select is((public.exchange_special('42000000-0000-0000-0000-000000000001','eagle')
  ->'wallet'->>'miao_coins')::int,-15,'lost receipt retry does not spend twice');
select throws_ok($$select public.exchange_special('42000000-0000-0000-0000-000000000002','eagle')$$,
  '22023','Insufficient special currency','cannot exchange without source balance');
select throws_ok($$select public.exchange_special('42000000-0000-0000-0000-000000000001','gem')$$,
  '42501','Exchange identity mismatch','request id cannot switch source currency');
select is((public.exchange_special('42000000-0000-0000-0000-000000000003','gem')
  ->'wallet'->>'miao_coins')::int,-10,'one gem converts to five miao coins');
select is((select gems from public.wallets where owner_id=auth.uid()),0,
  'one gem was spent');
select is((select issued from public.study_days where owner_id=auth.uid()
  and business_day='2026-09-01'),120,'exchange does not consume the study daily cap');
select is((select sum(miao_delta)::int from public.wallet_entries
  where owner_id=auth.uid() and kind like 'exchange_%'),10,
  'exchange ledger explains both five-coin credits');
select set_config('request.jwt.claims','{"sub":"40000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select public.bootstrap_identity();
select throws_ok($$select public.exchange_special('42000000-0000-0000-0000-000000000001','eagle')$$,
  '42501','Exchange identity mismatch','other owner cannot replay the same request id');
reset role;
select ok(not has_function_privilege('anon','public.exchange_special(uuid,text,integer)','EXECUTE'),
  'public anonymous role cannot exchange');
select * from finish();
rollback;
