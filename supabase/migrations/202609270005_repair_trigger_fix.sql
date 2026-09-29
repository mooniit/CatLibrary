-- Fix the single-member lookup: PostgreSQL has no min(uuid) aggregate.
create or replace function public.begin_single_repair_after_settlement() returns trigger
language plpgsql security definer set search_path='' as $$
declare member_count integer; owner uuid; balance integer; protected_through date;
begin
  select count(*) into member_count from public.family_members
    where family_id=new.family_id;
  if member_count<>1 then return new; end if;
  select user_id into owner from public.family_members
    where family_id=new.family_id;
  select max(grace_through) into protected_through from public.repair_episodes
    where family_id=new.family_id and status='completed';
  if new.business_day<=protected_through or exists(select 1 from public.repair_episodes
      where family_id=new.family_id and status in ('pending','active')) then
    return new;
  end if;
  select miao_coins into balance from public.wallets where owner_id=owner;
  if balance=-150 then
    insert into public.repair_episodes(family_id,status)
      values(new.family_id,'pending');
  end if;
  return new;
end; $$;
