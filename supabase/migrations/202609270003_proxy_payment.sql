-- T19: a previously capped owner's current cat fee may be paid by the other member.
create table public.proxy_payment_notices (
  payer_id uuid not null references public.wallets(owner_id),
  business_day date not null,
  total_paid integer not null check(total_paid between 1 and 80),
  acknowledged_at timestamptz,
  primary key(payer_id,business_day)
);
alter table public.proxy_payment_notices enable row level security;
revoke all on public.proxy_payment_notices from anon,authenticated;

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
  (kind in ('cat_fee','proxy_fee') and miao_delta between -20 and -1
    and eagle_delta=0 and gem_delta=0 and business_day is not null
    and operation_id is null)
);

-- Called only by the durable family-day finish trigger after all owners' own fees.
create function public.apply_family_proxy_charges() returns trigger
language plpgsql security definer set search_path='' as $$
declare row_data record; other_member uuid; balance integer; paid_now integer;
begin
  for row_data in select d.cat_id,d.owner_id,c.adopted_at from public.daily_cat_charges d
      join public.cats c on c.id=d.cat_id
      join public.daily_interest_charges i on i.owner_id=d.owner_id
        and i.business_day=d.business_day
      where c.family_id=new.family_id and d.business_day=new.business_day
        and d.status='owner_capped' and d.paid=0
        and i.balance_after_reward=-150
      order by c.adopted_at,c.id loop
    select user_id into other_member from public.family_members
      where family_id=new.family_id and user_id<>row_data.owner_id;
    if other_member is null then continue; end if;
    select miao_coins into balance from public.wallets
      where owner_id=other_member for update;
    paid_now := least(20,greatest(0,balance+150));
    if paid_now=0 then continue; end if;
    update public.wallets set miao_coins=miao_coins-paid_now
      where owner_id=other_member;
    update public.daily_cat_charges
      set payer_id=other_member,paid=paid_now,
        status=case when paid_now=20 then 'proxy' else 'proxy_capped' end
      where cat_id=row_data.cat_id and business_day=new.business_day;
    insert into public.wallet_entries(owner_id,kind,miao_delta,business_day)
      values(other_member,'proxy_fee',-paid_now,new.business_day);
    insert into public.proxy_payment_notices(payer_id,business_day,total_paid)
      values(other_member,new.business_day,paid_now)
      on conflict(payer_id,business_day) do update
        set total_paid=public.proxy_payment_notices.total_paid+excluded.total_paid;
  end loop;
  return new;
end; $$;
revoke all on function public.apply_family_proxy_charges()
  from public,anon,authenticated;
create trigger family_proxy_before_finish before insert on public.family_daily_settlements
  for each row execute function public.apply_family_proxy_charges();

create function public.proxy_notice_state() returns jsonb
language sql stable security definer set search_path='' as $$
  select coalesce(jsonb_agg(jsonb_build_object('day',business_day,
    'paid',total_paid) order by business_day),'[]'::jsonb)
  from public.proxy_payment_notices
  where payer_id=(select auth.uid()) and acknowledged_at is null;
$$;
create function public.ack_proxy_notice(target_day date) returns void
language plpgsql security definer set search_path='' as $$
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  update public.proxy_payment_notices set acknowledged_at=coalesce(acknowledged_at,clock_timestamp())
    where payer_id=auth.uid() and business_day=target_day;
end; $$;
revoke all on function public.proxy_notice_state(),public.ack_proxy_notice(date)
  from public,anon;
grant execute on function public.proxy_notice_state(),public.ack_proxy_notice(date)
  to authenticated;
