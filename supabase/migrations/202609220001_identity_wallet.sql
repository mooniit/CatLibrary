-- M1: the authenticated identity owns one wallet; clients never mint balances.
create table public.wallets (
  owner_id uuid primary key references auth.users(id) on delete cascade,
  miao_coins integer not null default 30 check(miao_coins >= -150),
  eagle_pounds integer not null default 0 check(eagle_pounds >= 0),
  gems integer not null default 0 check(gems >= 0),
  created_at timestamptz not null default now()
);
create table public.wallet_entries (
  id bigint generated always as identity primary key,
  owner_id uuid not null references public.wallets(owner_id) on delete cascade,
  kind text not null check(kind = 'initial'),
  miao_delta integer not null check(miao_delta = 30),
  created_at timestamptz not null default now(),
  unique(owner_id,kind)
);
alter table public.wallets enable row level security;
alter table public.wallet_entries enable row level security;
revoke all on public.wallets, public.wallet_entries from anon, authenticated;
grant select on public.wallets, public.wallet_entries to authenticated;
create policy own_wallet_read on public.wallets for select to authenticated
  using (owner_id = (select auth.uid()));
create policy own_wallet_entries_read on public.wallet_entries for select to authenticated
  using (owner_id = (select auth.uid()));
create function public.bootstrap_identity() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  current_owner uuid := auth.uid();
  inserted_owner uuid;
  result jsonb;
begin
  if current_owner is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  insert into public.wallets(owner_id) values(current_owner)
    on conflict(owner_id) do nothing returning owner_id into inserted_owner;
  if inserted_owner is not null then
    insert into public.wallet_entries(owner_id,kind,miao_delta)
      values(current_owner,'initial',30);
  end if;
  select jsonb_build_object('owner_id',owner_id,'miao_coins',miao_coins,
    'eagle_pounds',eagle_pounds,'gems',gems) into result
    from public.wallets where owner_id=current_owner;
  return result;
end;
$$;
revoke all on function public.bootstrap_identity() from public, anon;
grant execute on function public.bootstrap_identity() to authenticated;
