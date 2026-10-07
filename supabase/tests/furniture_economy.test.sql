begin;
select no_plan();
select is((select count(*)::integer from public.furniture_products where not is_test and active and currency='miao' and purchase_limit=1),36,'all 36 approved styles are active and unique per household');
select is((select count(*)::integer from public.furniture_products p join (values
  ('bookshelf',120),('desk',100),('chair',40),('tree',140),('bed',60),('window',60),('rug',80),('wall',100),('floor',100),('frame',30)
) b(kind,price) on b.kind=p.kind join (values ('wood',1::numeric),('lunar',1.5::numeric),('royal',2::numeric)) t(theme,multiplier)
on t.theme=p.theme where not p.is_test and p.price=b.price*t.multiplier),36,'approved price matrix is authoritative');
insert into auth.users(id) values ('76000000-0000-0000-0000-000000000001'),('76000000-0000-0000-0000-000000000002');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"76000000-0000-0000-0000-000000000001"}',true);
select public.bootstrap_identity(); select public.create_family();
select set_config('request.jwt.claims','{"sub":"76000000-0000-0000-0000-000000000002"}',true);
select public.bootstrap_identity();
reset role;
insert into public.family_members(family_id,user_id) select family_id,'76000000-0000-0000-0000-000000000002' from public.family_members where user_id='76000000-0000-0000-0000-000000000001';
update public.wallets set miao_coins=100 where owner_id in ('76000000-0000-0000-0000-000000000001','76000000-0000-0000-0000-000000000002');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"76000000-0000-0000-0000-000000000001"}',true);
select is(public.purchase_furniture('76100000-0000-0000-0000-000000000001','wood-chair')->>'status','purchased','first family copy purchased');
select is((select miao_coins from public.wallets where owner_id=auth.uid()),60,'confirmed 40 coin price charged');
select is(public.purchase_furniture('76100000-0000-0000-0000-000000000001','wood-chair')->>'status','purchased','same request still returns success');
select is((select miao_coins from public.wallets where owner_id=auth.uid()),60,'receipt retry does not charge twice');
select is(public.purchase_furniture('76100000-0000-0000-0000-000000000002','wood-chair')->>'reason','purchase_limit','buyer cannot buy second same style');
select set_config('request.jwt.claims','{"sub":"76000000-0000-0000-0000-000000000002"}',true);
select is(public.purchase_furniture('76100000-0000-0000-0000-000000000003','wood-chair')->>'reason','purchase_limit','partner shares the same unique cap');
select is((select miao_coins from public.wallets where owner_id=auth.uid()),100,'partner rejected without charge');
select is(jsonb_array_length(public.furniture_state()->'inventory'),1,'family only owns one instance');
select is(public.purchase_furniture('76100000-0000-0000-0000-000000000004','lunar-chair')->>'status','purchased','another style is separately unique');
select * from finish();
rollback;
