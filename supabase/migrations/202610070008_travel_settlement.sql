-- T29 actual trip intervals integrated with M4 repair, grace and proxy ordering.
create or replace function public.settle_family_day(target_family uuid, bill_day date)
returns jsonb language plpgsql security definer set search_path='' as $$
declare member record; cat_row record; balance integer; interest_due integer;
  paid integer; cutoff timestamptz; member_count integer; capped_count integer;
  protected_through date; mode_now text:='normal';
begin
  if target_family is null or bill_day is null then
    raise exception 'Family and billing day required' using errcode='22023';
  end if;
  cutoff:=(bill_day+1)::timestamp at time zone 'Asia/Shanghai';
  perform 1 from public.families where id=target_family for update;
  if not found then raise exception 'Family not found' using errcode='22023'; end if;
  if exists(select 1 from public.family_daily_settlements
      where family_id=target_family and business_day=bill_day) then
    return jsonb_build_object('status','already_settled','business_day',bill_day);
  end if;

  -- Previously eligible online evidence may still pay; repair intervals are
  -- excluded by rewardable_ms, and late offline records never rewrite this day.
  for member in select user_id from public.family_members
      where family_id=target_family order by user_id loop
    perform public.settle_study_for_owner(member.user_id,cutoff);
    perform public.settle_tasks_for_owner(member.user_id);
  end loop;

  if exists(select 1 from public.repair_episodes where family_id=target_family
      and status in ('pending','active')) then
    mode_now:='repair';
  else
    select max(grace_through) into protected_through from public.repair_episodes
      where family_id=target_family and status='completed';
    if bill_day<=protected_through then mode_now:='grace'; end if;
  end if;

  -- Both members must still be capped after this zero's eligible rewards.
  -- A member who reaches the cap later in this settlement waits until next day.
  if mode_now='normal' then
    select count(*),count(*) filter(where w.miao_coins=-150)
      into member_count,capped_count from public.family_members m
      join public.wallets w on w.owner_id=m.user_id
      where m.family_id=target_family;
    if member_count=2 and capped_count=2 then
      insert into public.repair_episodes(family_id,status)
        values(target_family,'pending');
      mode_now:='repair';
    end if;
  end if;

  if mode_now<>'normal' then
    insert into public.daily_cat_charges
      (cat_id,business_day,owner_id,due,paid,status)
      select c.id,bill_day,c.owner_id,0,0,mode_now
      from public.cats c where c.family_id=target_family and c.adopted_at<cutoff;
    insert into public.family_daily_settlements(family_id,business_day,mode)
      values(target_family,bill_day,mode_now);
    return jsonb_build_object('status','settled','business_day',bill_day,
      'mode',mode_now);
  end if;

  for member in select user_id from public.family_members
      where family_id=target_family order by user_id loop
    select miao_coins into balance from public.wallets
      where owner_id=member.user_id for update;
    interest_due:=case when balance<0 then (-balance)/10 else 0 end;
    paid:=least(interest_due,greatest(0,balance+150));
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
    -- Historical intervals remain authoritative after return and scheduler delay.
    if exists(select 1 from public.cat_trips t where t.cat_id=cat_row.id
        and t.started_at<=cutoff and t.ends_at>cutoff) then
      insert into public.daily_cat_charges(cat_id,business_day,owner_id,due,paid,status)
        values(cat_row.id,bill_day,cat_row.owner_id,0,0,'travel');
      continue;
    end if;
    if exists(select 1 from public.cat_feedings f
        where f.cat_id=cat_row.id and f.business_day=bill_day) then
      insert into public.daily_cat_charges
        (cat_id,business_day,owner_id,due,paid,status)
        values(cat_row.id,bill_day,cat_row.owner_id,0,0,'fed');
      continue;
    end if;
    select miao_coins into balance from public.wallets
      where owner_id=cat_row.owner_id for update;
    paid:=least(20,greatest(0,balance+150));
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
  insert into public.family_daily_settlements(family_id,business_day,mode)
    values(target_family,bill_day,'normal');
  return jsonb_build_object('status','settled','business_day',bill_day,
    'mode','normal');
end; $$;
