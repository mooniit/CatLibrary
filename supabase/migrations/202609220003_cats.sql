create table public.cats (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id),
  owner_id uuid not null references auth.users(id),
  appearance text not null check(appearance in ('black_short','light_long')),
  name text not null check(length(btrim(name))>0),
  adopted_at timestamptz not null default now(),
  unique(owner_id,appearance),
  unique(family_id,name)
);
alter table public.cats enable row level security;
revoke all on public.cats from anon,authenticated;
create function public.cats_state() returns jsonb
language plpgsql security definer set search_path='' as $$
declare me uuid:=auth.uid(); home uuid;
begin
  if me is null then raise exception 'Authentication required' using errcode='42501'; end if;
  select family_id into home from public.family_members where user_id=me;
  return jsonb_build_object('family_id',home,'remaining',2-(select count(*) from public.cats where owner_id=me),
    'cats',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'appearance',appearance,'owner_id',owner_id,'is_mine',owner_id=me) order by adopted_at,id) from public.cats where family_id=home),'[]'::jsonb));
end; $$;
create function public.adopt_cat(appearance_key text, cat_name text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare me uuid:=auth.uid(); home uuid; existing public.cats; chosen_name text:=btrim(cat_name,E' \t\n\r');
begin
  if me is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if appearance_key is null or appearance_key not in ('black_short','light_long') then raise exception 'Invalid appearance'; end if;
  if chosen_name is null or length(chosen_name)=0 then raise exception 'Cat name required'; end if;
  select family_id into home from public.family_members where user_id=me;
  if home is null then raise exception 'Join or create a family first'; end if;
  -- Serialize family naming and quota decisions. No wallet mutation: adoption is free.
  perform 1 from public.families where id=home for update;
  select * into existing from public.cats where owner_id=me and appearance=appearance_key;
  if existing.id is not null then
    if existing.name=chosen_name then return public.cats_state(); end if;
    raise exception 'Appearance already adopted';
  end if;
  if (select count(*) from public.cats where owner_id=me)>=2 then raise exception 'Adoption quota reached'; end if;
  if exists(select 1 from public.cats where family_id=home and name=chosen_name) then raise exception 'Cat name already used'; end if;
  insert into public.cats(family_id,owner_id,appearance,name) values(home,me,appearance_key,chosen_name);
  return public.cats_state();
end; $$;
revoke all on function public.cats_state(),public.adopt_cat(text,text) from public,anon;
grant execute on function public.cats_state(),public.adopt_cat(text,text) to authenticated;
