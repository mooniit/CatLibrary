-- T20: durable repair episode and first-online 72-hour window.
create table public.repair_episodes (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id),
  triggered_at timestamptz not null default clock_timestamp(),
  status text not null check(status in ('pending','active','completed')),
  completed_at timestamptz,
  grace_through date
);
create unique index one_open_repair on public.repair_episodes(family_id)
  where status in ('pending','active');
create table public.repair_windows (
  id uuid primary key default gen_random_uuid(),
  episode_id uuid not null references public.repair_episodes(id),
  cycle_no integer not null check(cycle_no>=1),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  progress_ms bigint not null default 0 check(progress_ms>=0),
  status text not null check(status in ('active','failed','completed')),
  unique(episode_id,cycle_no),
  check(ends_at=starts_at+interval '72 hours')
);
alter table public.repair_episodes enable row level security;
alter table public.repair_windows enable row level security;
revoke all on public.repair_episodes,public.repair_windows from anon,authenticated;

create function public.begin_single_repair_after_settlement() returns trigger
language plpgsql security definer set search_path='' as $$
declare member_count integer; owner uuid; balance integer; protected_through date;
begin
  select count(*),min(user_id) into member_count,owner
    from public.family_members where family_id=new.family_id;
  if member_count<>1 then return new; end if;
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
revoke all on function public.begin_single_repair_after_settlement()
  from public,anon,authenticated;
create trigger single_repair_after_settlement
  after insert on public.family_daily_settlements
  for each row execute function public.begin_single_repair_after_settlement();

create function public.repair_state() returns jsonb
language plpgsql security definer set search_path='' as $$
declare me uuid:=auth.uid(); home uuid; episode public.repair_episodes;
  window_row public.repair_windows; started timestamptz;
begin
  if me is null then raise exception 'Authentication required' using errcode='42501'; end if;
  select family_id into home from public.family_members where user_id=me;
  if home is null then return jsonb_build_object('status','none'); end if;
  perform 1 from public.families where id=home for update;
  select * into episode from public.repair_episodes
    where family_id=home and status in ('pending','active')
    order by triggered_at desc limit 1;
  if not found then
    return jsonb_build_object('status','none',
      'grace_through',(select max(grace_through) from public.repair_episodes
        where family_id=home and status='completed'));
  end if;
  if episode.status='pending' then
    started:=clock_timestamp();
    insert into public.repair_windows
      (episode_id,cycle_no,starts_at,ends_at,status)
      values(episode.id,1,started,started+interval '72 hours','active');
    update public.repair_episodes set status='active' where id=episode.id;
  end if;
  select * into window_row from public.repair_windows
    where episode_id=episode.id order by cycle_no desc limit 1;
  return jsonb_build_object('status','active','episode_id',episode.id,
    'window_id',window_row.id,'cycle_no',window_row.cycle_no,
    'starts_at',window_row.starts_at,'ends_at',window_row.ends_at,
    'progress_ms',window_row.progress_ms,'target_ms',7200000);
end; $$;
revoke all on function public.repair_state() from public,anon;
grant execute on function public.repair_state() to authenticated;
