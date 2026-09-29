-- T18: deterministic family-day settlement. The scheduler is added after Q08/Q10.
create table public.family_daily_settlements (
  family_id uuid not null references public.families(id),
  business_day date not null,
  settled_at timestamptz not null default clock_timestamp(),
  primary key(family_id,business_day)
);
create table public.daily_interest_charges (
  owner_id uuid not null references public.wallets(owner_id),
  business_day date not null,
  balance_after_reward integer not null,
  due integer not null check(due between 0 and 15),
  paid integer not null check(paid between 0 and due),
  primary key(owner_id,business_day)
);
create table public.daily_cat_charges (
  cat_id uuid not null references public.cats(id),
  business_day date not null,
  owner_id uuid not null references public.wallets(owner_id),
  payer_id uuid references public.wallets(owner_id),
  due integer not null check(due in (0,20)),
  paid integer not null check(paid between 0 and due),
  status text not null check(status in
    ('fed','owner','owner_capped','proxy','proxy_capped','travel','repair','grace')),
  primary key(cat_id,business_day),
  check((paid=0 and payer_id is null) or (paid>0 and payer_id is not null))
);
alter table public.family_daily_settlements enable row level security;
alter table public.daily_interest_charges enable row level security;
alter table public.daily_cat_charges enable row level security;
revoke all on public.family_daily_settlements,public.daily_interest_charges,
  public.daily_cat_charges from anon,authenticated;

alter table public.wallet_entries drop constraint wallet_entry_reward_shape;
alter table public.wallet_entries add constraint wallet_entry_reward_shape check (
  (kind='initial' and miao_delta=30 and eagle_delta=0 and gem_delta=0
    and business_day is null and operation_id is null) or
  (kind='study' and miao_delta>0 and miao_delta<=120 and eagle_delta=0 and gem_delta=0
    and business_day is not null and operation_id is null) or
  (kind='task_language' and miao_delta=0 and eagle_delta between 1 and 12 and gem_delta=0
    and business_day is not null and operation_id is null) or
  (kind='task_exercise' and miao_delta=0 and eagle_delta=0 and gem_delta between 1 and 12
    and business_day is not null and operation_id is null) or
  (kind='exchange_eagle' and miao_delta=5 and eagle_delta=-1 and gem_delta=0
    and business_day is null and operation_id is not null) or
  (kind='exchange_gem' and miao_delta=5 and eagle_delta=0 and gem_delta=-1
    and business_day is null and operation_id is not null) or
  (kind='weekly' and miao_delta=0 and eagle_delta=6 and gem_delta=6
    and business_day is null and operation_id is not null) or
  (kind='feeding' and miao_delta=-15 and eagle_delta=0 and gem_delta=0
    and business_day is not null and operation_id is null) or
  (kind='interest' and miao_delta between -15 and -1
    and eagle_delta=0 and gem_delta=0 and business_day is not null
    and operation_id is null) or
  (kind='cat_fee' and miao_delta between -20 and -1
    and eagle_delta=0 and gem_delta=0 and business_day is not null
    and operation_id is null)
);

create function public.settle_family_day(target_family uuid, bill_day date)
returns jsonb language plpgsql security definer set search_path='' as $$
declare member record; cat_row record; balance integer; interest_due integer;
  paid integer; cutoff timestamptz;
begin
  if target_family is null or bill_day is null then
    raise exception 'Family and billing day required' using errcode='22023';
  end if;
  cutoff := (bill_day+1)::timestamp at time zone 'Asia/Shanghai';
  perform 1 from public.families where id=target_family for update;
  if not found then raise exception 'Family not found' using errcode='22023'; end if;
  if exists(select 1 from public.family_daily_settlements
      where family_id=target_family and business_day=bill_day) then
    return jsonb_build_object('status','already_settled','business_day',bill_day);
  end if;

  -- All eligible rewards precede every interest and cat fee in this family.
  for member in select user_id from public.family_members
      where family_id=target_family order by user_id loop
    perform public.settle_study_for_owner(member.user_id,cutoff);
    perform public.settle_tasks_for_owner(member.user_id);
  end loop;

  for member in select user_id from public.family_members
      where family_id=target_family order by user_id loop
    select miao_coins into balance from public.wallets
      where owner_id=member.user_id for update;
    interest_due := case when balance<0 then (-balance)/10 else 0 end;
    paid := least(interest_due,greatest(0,balance+150));
    insert into public.daily_interest_charges
      (owner_id,business_day,balance_after_reward,due,paid)
      values(member.user_id,bill_day,balance,interest_due,paid);
    if paid>0 then
      update public.wallets set miao_coins=miao_coins-paid
        where owner_id=member.user_id;
      insert into public.wallet_entries(owner_id,kind,miao_delta,business_day)
        values(member.user_id,'interest',-paid,bill_day);
    end if;
  end loop;

  for cat_row in select c.id,c.owner_id from public.cats c
      where c.family_id=target_family and c.adopted_at<cutoff
      order by c.owner_id,c.adopted_at,c.id loop
    if exists(select 1 from public.cat_feedings f
        where f.cat_id=cat_row.id and f.business_day=bill_day) then
      insert into public.daily_cat_charges
        (cat_id,business_day,owner_id,due,paid,status)
        values(cat_row.id,bill_day,cat_row.owner_id,0,0,'fed');
      continue;
    end if;
    select miao_coins into balance from public.wallets
      where owner_id=cat_row.owner_id for update;
    paid := least(20,greatest(0,balance+150));
    insert into public.daily_cat_charges
      (cat_id,business_day,owner_id,payer_id,due,paid,status)
      values(cat_row.id,bill_day,cat_row.owner_id,
        case when paid>0 then cat_row.owner_id else null end,
        20,paid,case when paid=20 then 'owner' else 'owner_capped' end);
    if paid>0 then
      update public.wallets set miao_coins=miao_coins-paid
        where owner_id=cat_row.owner_id;
      insert into public.wallet_entries(owner_id,kind,miao_delta,business_day)
        values(cat_row.owner_id,'cat_fee',-paid,bill_day);
    end if;
  end loop;
  insert into public.family_daily_settlements(family_id,business_day)
    values(target_family,bill_day);
  return jsonb_build_object('status','settled','business_day',bill_day);
end; $$;
revoke all on function public.settle_family_day(uuid,date)
  from public,anon,authenticated;
