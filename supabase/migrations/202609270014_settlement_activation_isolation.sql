-- Billing starts when this rule is installed; prototype days are not back-billed.
create table public.billing_activation (
  singleton boolean primary key default true check(singleton),
  start_day date not null
);
insert into public.billing_activation(singleton,start_day)
  values(true,(clock_timestamp() at time zone 'Asia/Shanghai')::date);
alter table public.billing_activation enable row level security;
revoke all on public.billing_activation from anon,authenticated;

-- One malformed family must not roll back every other family's settlement.
create table public.family_settlement_failures (
  family_id uuid not null references public.families(id),
  business_day date not null,
  attempts integer not null default 1 check(attempts>0),
  last_error text not null,
  last_at timestamptz not null default clock_timestamp(),
  primary key(family_id,business_day)
);
alter table public.family_settlement_failures enable row level security;
revoke all on public.family_settlement_failures from anon,authenticated;

create or replace function public.settle_due_family_days(
  as_of timestamptz default clock_timestamp())
returns integer language plpgsql security definer set search_path='' as $$
declare home record; day_to_bill date; last_day date; activation_day date;
  completed integer:=0;
begin
  last_day:=(as_of at time zone 'Asia/Shanghai')::date-1;
  select start_day into activation_day from public.billing_activation
    where singleton=true;
  -- ponytail: hourly history scan fits a two-person beta; track the last
  -- contiguous settlement day if family age makes this measurable.
  for home in select id,(created_at at time zone 'Asia/Shanghai')::date as first_day
      from public.families order by created_at,id loop
    for day_to_bill in select day::date from generate_series(
        greatest(home.first_day,activation_day)::timestamp,
        last_day::timestamp,interval '1 day') day loop
      if not exists(select 1 from public.family_daily_settlements
          where family_id=home.id and business_day=day_to_bill) then
        begin
          perform public.settle_family_day(home.id,day_to_bill);
          delete from public.family_settlement_failures
            where family_id=home.id and business_day=day_to_bill;
          completed:=completed+1;
        exception when others then
          insert into public.family_settlement_failures
            (family_id,business_day,last_error)
            values(home.id,day_to_bill,sqlerrm)
            on conflict(family_id,business_day) do update
              set attempts=public.family_settlement_failures.attempts+1,
                  last_error=excluded.last_error,
                  last_at=clock_timestamp();
          exit;
        end;
      end if;
    end loop;
  end loop;
  return completed;
end; $$;
