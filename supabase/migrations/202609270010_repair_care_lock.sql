-- T20: repair pauses active care actions while keeping the family readable.
create function public.reject_care_during_repair() returns trigger
language plpgsql security definer set search_path='' as $$
declare home uuid;
begin
  if tg_table_name='cats' then
    home:=new.family_id;
  else
    select family_id into home from public.cats where id=new.cat_id;
  end if;
  if exists(select 1 from public.repair_episodes
      where family_id=home and status in ('pending','active')) then
    raise exception 'Repair in progress' using errcode='22023';
  end if;
  return new;
end; $$;
revoke all on function public.reject_care_during_repair()
  from public,anon,authenticated;
create trigger cat_adoption_repair_guard before insert on public.cats
  for each row execute function public.reject_care_during_repair();
create trigger cat_feeding_repair_guard before insert on public.cat_feedings
  for each row execute function public.reject_care_during_repair();

create or replace function public.cats_state() returns jsonb
language plpgsql security definer set search_path='' as $$
declare me uuid:=auth.uid(); home uuid;
  today date:=(clock_timestamp() at time zone 'Asia/Shanghai')::date;
begin
  if me is null then raise exception 'Authentication required' using errcode='42501'; end if;
  select family_id into home from public.family_members where user_id=me;
  return jsonb_build_object(
    'family_id',home,
    'repairing',exists(select 1 from public.repair_episodes
      where family_id=home and status in ('pending','active')),
    'remaining',2-(select count(*) from public.cats where owner_id=me),
    'wallet',(select jsonb_build_object('owner_id',owner_id,'miao_coins',miao_coins,
      'eagle_pounds',eagle_pounds,'gems',gems) from public.wallets where owner_id=me),
    'cats',coalesce((select jsonb_agg(jsonb_build_object(
      'id',c.id,'name',c.name,'appearance',c.appearance,'owner_id',c.owner_id,
      'is_mine',c.owner_id=me,'fed_today',f.cat_id is not null,
      'fed_by',f.payer_id) order by c.adopted_at,c.id)
      from public.cats c left join public.cat_feedings f
        on f.cat_id=c.id and f.business_day=today
      where c.family_id=home),'[]'::jsonb)
  );
end; $$;
