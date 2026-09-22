create table public.families (
  id uuid primary key default gen_random_uuid(),
  creator_id uuid not null unique references auth.users(id),
  invite_code text not null unique default replace(gen_random_uuid()::text,'-',''),
  created_at timestamptz not null default now()
);
create table public.family_members (
  user_id uuid primary key references auth.users(id),
  family_id uuid not null references public.families(id),
  joined_at timestamptz not null default now()
);
create index family_members_family on public.family_members(family_id);
create table public.family_join_requests (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id),
  applicant_id uuid not null references auth.users(id),
  status text not null default 'pending' check(status in ('pending','approved','rejected')),
  created_at timestamptz not null default now(),
  unique(family_id,applicant_id)
);
alter table public.families enable row level security;
alter table public.family_members enable row level security;
alter table public.family_join_requests enable row level security;
-- Access is only through scoped RPCs. No direct member enumeration or mutations.
revoke all on public.families,public.family_members,public.family_join_requests from anon,authenticated;

create function public.family_state() returns jsonb
language plpgsql security definer set search_path='' as $$
declare me uuid:=auth.uid(); home public.families; result jsonb;
begin
  if me is null then raise exception 'Authentication required' using errcode='42501'; end if;
  select f.* into home from public.families f join public.family_members m on m.family_id=f.id where m.user_id=me;
  if home.id is null then
    return jsonb_build_object('family',null,'members','[]'::jsonb,'requests',coalesce((select jsonb_agg(jsonb_build_object('id',id,'status',status,'created_at',created_at) order by created_at) from public.family_join_requests where applicant_id=me),'[]'::jsonb));
  end if;
  return jsonb_build_object('family',jsonb_build_object('id',home.id,'is_creator',home.creator_id=me,'invite_code',case when home.creator_id=me then home.invite_code else null end),
    'members',coalesce((select jsonb_agg(jsonb_build_object('user_id',user_id,'is_me',user_id=me) order by joined_at) from public.family_members where family_id=home.id),'[]'::jsonb),
    'requests',case when home.creator_id=me then coalesce((select jsonb_agg(jsonb_build_object('id',id,'applicant_id',applicant_id,'status',status,'created_at',created_at) order by created_at) from public.family_join_requests where family_id=home.id and status='pending'),'[]'::jsonb) else '[]'::jsonb end);
end; $$;

create function public.create_family() returns jsonb
language plpgsql security definer set search_path='' as $$
declare me uuid:=auth.uid(); home_id uuid;
begin
  if me is null then raise exception 'Authentication required' using errcode='42501'; end if;
  perform pg_advisory_xact_lock(hashtextextended(me::text,0));
  if exists(select 1 from public.family_members where user_id=me) then return public.family_state(); end if;
  insert into public.families(creator_id) values(me) returning id into home_id;
  insert into public.family_members(user_id,family_id) values(me,home_id);
  return public.family_state();
end; $$;

create function public.request_family_join(code text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare me uuid:=auth.uid(); home_id uuid;
begin
  if me is null then raise exception 'Authentication required' using errcode='42501'; end if;
  perform pg_advisory_xact_lock(hashtextextended(me::text,0));
  if exists(select 1 from public.family_members where user_id=me) then raise exception 'Already in a family'; end if;
  select id into home_id from public.families where invite_code=lower(btrim(code));
  if home_id is null then raise exception 'Invalid invitation code'; end if;
  if (select count(*) from public.family_members where family_id=home_id)>=2 then raise exception 'Family is full'; end if;
  insert into public.family_join_requests(family_id,applicant_id) values(home_id,me)
    on conflict(family_id,applicant_id) do update set status='pending';
  return public.family_state();
end; $$;

create function public.decide_family_join(request_id uuid, approve boolean) returns jsonb
language plpgsql security definer set search_path='' as $$
declare me uuid:=auth.uid(); req public.family_join_requests; creator uuid;
begin
  if me is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if approve is null then raise exception 'Decision required'; end if;
  select r.* into req from public.family_join_requests r where r.id=request_id;
  select creator_id into creator from public.families where id=req.family_id;
  if creator is distinct from me then raise exception 'Only inviter may decide' using errcode='42501'; end if;
  -- Same lock order as create/join: applicant first, then the home capacity row.
  perform pg_advisory_xact_lock(hashtextextended(req.applicant_id::text,0));
  perform 1 from public.families where id=req.family_id for update;
  select * into req from public.family_join_requests where id=request_id for update;
  if req.status<>'pending' then return public.family_state(); end if;
  if approve then
    if exists(select 1 from public.family_members where user_id=req.applicant_id) then raise exception 'Applicant already in a family'; end if;
    if (select count(*) from public.family_members where family_id=req.family_id)>=2 then raise exception 'Family is full'; end if;
    insert into public.family_members(user_id,family_id) values(req.applicant_id,req.family_id);
  end if;
  update public.family_join_requests set status=case when approve then 'approved' else 'rejected' end where id=request_id;
  return public.family_state();
end; $$;
revoke all on function public.family_state(),public.create_family(),public.request_family_join(text),public.decide_family_join(uuid,boolean) from public,anon;
grant execute on function public.family_state(),public.create_family(),public.request_family_join(text),public.decide_family_join(uuid,boolean) to authenticated;
