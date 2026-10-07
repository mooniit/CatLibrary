-- T30/T31: rewards and album records commit together, independent of app uptime.
alter table public.furniture_inventory add column source_cat_id uuid references public.cats(id);
alter table public.furniture_inventory add column source_trip_id uuid references public.cat_trips(id);
create unique index one_trip_souvenir on public.furniture_inventory(source_trip_id) where source_trip_id is not null;
create table public.travel_return_seen (
  user_id uuid not null references auth.users(id), trip_id uuid not null references public.cat_trips(id),
  primary key(user_id,trip_id)
);
create table public.travel_return_failures (
  family_id uuid primary key references public.families(id), attempts integer not null default 1,
  last_error text not null, last_at timestamptz not null default clock_timestamp()
);
alter table public.travel_return_seen enable row level security;
alter table public.travel_return_failures enable row level security;
revoke all on public.travel_return_seen,public.travel_return_failures from anon,authenticated;
create function public.return_family_trips(home uuid,as_of timestamptz default clock_timestamp()) returns integer
language plpgsql security definer set search_path='' as $$
declare trip public.cat_trips; item uuid; completed integer:=0; sku_key text;
begin
  perform 1 from public.families where id=home for update;
  if not found then return 0; end if;
  for trip in select * from public.cat_trips where family_id=home and returned_at is null and ends_at<=as_of order by ends_at,id for update loop
    if not exists(select 1 from public.cat_travel_visits where cat_id=trip.cat_id and destination=trip.destination) then
      select souvenir_sku into sku_key from public.travel_destinations where id=trip.destination;
      insert into public.furniture_inventory(family_id,sku,source,source_id,source_cat_id,source_trip_id)
        values(home,sku_key,'souvenir',trip.id,trip.cat_id,trip.id) returning id into item;
      insert into public.cat_travel_visits(cat_id,destination,trip_id,inventory_id) values(trip.cat_id,trip.destination,trip.id,item);
    end if;
    update public.cat_trips set returned_at=as_of where id=trip.id;
    completed:=completed+1;
  end loop;
  return completed;
end $$;
revoke all on function public.return_family_trips(uuid,timestamptz) from public,anon,authenticated;
create function public.return_due_cat_trips() returns integer
language plpgsql security definer set search_path='' as $$
declare home record; n integer:=0;
begin
  for home in select distinct family_id from public.cat_trips where returned_at is null and ends_at<=clock_timestamp() order by family_id loop
    begin
      n:=n+public.return_family_trips(home.family_id);
      delete from public.travel_return_failures where family_id=home.family_id;
    exception when others then
      insert into public.travel_return_failures(family_id,last_error) values(home.family_id,sqlerrm)
        on conflict(family_id) do update set attempts=public.travel_return_failures.attempts+1,last_error=excluded.last_error,last_at=clock_timestamp();
    end;
  end loop;
  return n;
end $$;
revoke all on function public.return_due_cat_trips() from public,anon,authenticated;
select cron.schedule('cat-travel-returns','* * * * *','select public.return_due_cat_trips()');

-- Internal implementations keep their privileges revoked after rename.
alter function public.start_cat_travel(uuid,uuid,uuid) rename to start_cat_travel_transaction;
revoke all on function public.start_cat_travel_transaction(uuid,uuid,uuid) from public,anon,authenticated;
create function public.start_cat_travel(request_id uuid,target_cat uuid,target_family uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if exists(select 1 from public.family_members where user_id=auth.uid() and family_id=target_family) then
    perform public.return_family_trips(target_family);
  end if;
  return public.start_cat_travel_transaction(request_id,target_cat,target_family);
end $$;
alter function public.travel_state() rename to travel_state_base;
revoke all on function public.travel_state_base() from public,anon,authenticated;
create function public.travel_state() returns jsonb
language plpgsql security definer set search_path='' as $$
declare me uuid:=auth.uid(); home uuid;
begin
  if me is null then raise exception 'Authentication required' using errcode='42501'; end if;
  select family_id into home from public.family_members where user_id=me;
  perform public.return_family_trips(home);
  return public.travel_state_base()||jsonb_build_object('returns',coalesce((
    select jsonb_agg(jsonb_build_object('id',t.id,'cat_id',c.id,'cat_name',c.name,'destination',t.destination,
      'destination_label',d.label,'ends_at',t.ends_at,'first_visit',v.id is not null) order by t.ends_at desc,t.id)
    from public.cat_trips t join public.cats c on c.id=t.cat_id join public.travel_destinations d on d.id=t.destination
    left join public.cat_travel_visits v on v.trip_id=t.id
    where t.family_id=home and t.returned_at is not null and not exists(
      select 1 from public.travel_return_seen s where s.user_id=me and s.trip_id=t.id)),'[]'::jsonb));
end $$;
create function public.ack_travel_return(target_trip uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if not exists(select 1 from public.cat_trips t join public.family_members m on m.family_id=t.family_id
      where t.id=target_trip and m.user_id=auth.uid() and t.returned_at is not null) then
    raise exception 'Trip is outside your family or not returned' using errcode='42501'; end if;
  insert into public.travel_return_seen values(auth.uid(),target_trip) on conflict do nothing;
end $$;
create function public.family_album() returns jsonb
language plpgsql security definer set search_path='' as $$
declare me uuid:=auth.uid(); home uuid;
begin
  if me is null then raise exception 'Authentication required' using errcode='42501'; end if;
  select family_id into home from public.family_members where user_id=me;
  perform public.return_family_trips(home);
  return jsonb_build_object('family_id',home,'server_time',clock_timestamp(),
    'photos',coalesce((select jsonb_agg(jsonb_build_object('id',v.id,'cat_id',c.id,'cat_name',c.name,'appearance',c.appearance,
      'destination',d.id,'destination_label',d.label,'taken_at',t.ends_at,'arranged_by',t.arranged_by,
      'arranger_label',case when t.arranged_by=me then '我' else '另一位成员' end,'inventory_id',v.inventory_id,
      'souvenir_label',p.label,'illustration_status','pending_m7') order by t.ends_at desc,v.id)
      from public.cat_travel_visits v join public.cat_trips t on t.id=v.trip_id join public.cats c on c.id=v.cat_id
      join public.travel_destinations d on d.id=v.destination join public.furniture_inventory i on i.id=v.inventory_id
      join public.furniture_products p on p.sku=i.sku where t.family_id=home),'[]'::jsonb));
end $$;
revoke all on function public.start_cat_travel(uuid,uuid,uuid),public.travel_state(),public.family_album(),public.ack_travel_return(uuid) from public,anon;
grant execute on function public.start_cat_travel(uuid,uuid,uuid),public.travel_state(),public.family_album(),public.ack_travel_return(uuid) to authenticated;

alter function public.cats_state() rename to cats_state_care;
revoke all on function public.cats_state_care() from public,anon,authenticated;
create function public.cats_state() returns jsonb
language plpgsql security definer set search_path='' as $$
declare state jsonb; home uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  select family_id into home from public.family_members where user_id=auth.uid();
  perform public.return_family_trips(home);
  state:=public.cats_state_care();
  return state||jsonb_build_object('cats',coalesce((select jsonb_agg(c.value||jsonb_build_object('traveling',t.id is not null,'travel_ends_at',t.ends_at) order by c.ordinality)
    from jsonb_array_elements(state->'cats') with ordinality c(value,ordinality)
    left join public.cat_trips t on t.cat_id=(c.value->>'id')::uuid and t.returned_at is null and t.ends_at>clock_timestamp()),'[]'::jsonb));
end $$;
alter function public.feed_cat(uuid) rename to feed_cat_care;
revoke all on function public.feed_cat_care(uuid) from public,anon,authenticated;
create function public.feed_cat(target_cat uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare home uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  select family_id into home from public.family_members where user_id=auth.uid();
  if not exists(select 1 from public.cats where id=target_cat and family_id=home) then
    return public.feed_cat_care(target_cat); end if;
  perform 1 from public.families where id=home for update;
  if exists(select 1 from public.cat_trips where cat_id=target_cat and started_at<=clock_timestamp() and ends_at>clock_timestamp()) then
    return public.cats_state()||jsonb_build_object('outcome','traveling');
  end if;
  return public.feed_cat_care(target_cat);
end $$;
revoke all on function public.cats_state(),public.feed_cat(uuid) from public,anon;
grant execute on function public.cats_state(),public.feed_cat(uuid) to authenticated;

-- Surface provenance without changing inventory identity or editing the layout.
alter function public.furniture_state() rename to furniture_state_base;
revoke all on function public.furniture_state_base() from public,anon,authenticated;
create function public.furniture_state() returns jsonb
language plpgsql security definer set search_path='' as $$
declare home uuid; state jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  select family_id into home from public.family_members where user_id=auth.uid();
  perform public.return_family_trips(home);
  state:=public.furniture_state_base();
  return state||jsonb_build_object('inventory',coalesce((select jsonb_agg(to_jsonb(i)||jsonb_build_object('source_cat_name',c.name,'source_destination',d.label,'source_date',t.ends_at) order by i.created_at,i.id)
    from public.furniture_inventory i left join public.cats c on c.id=i.source_cat_id
    left join public.cat_trips t on t.id=i.source_trip_id left join public.travel_destinations d on d.id=t.destination
    where i.family_id=home),'[]'::jsonb));
end $$;
revoke all on function public.furniture_state() from public,anon;
grant execute on function public.furniture_state() to authenticated;
