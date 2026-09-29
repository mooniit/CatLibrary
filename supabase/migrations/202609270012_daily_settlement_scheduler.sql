-- Run at Beijing 00:01 and every later hour to catch up after a paused project.
create function public.settle_due_family_days(as_of timestamptz default clock_timestamp())
returns integer language plpgsql security definer set search_path='' as $$
declare home record; day_to_bill date; last_day date;
  completed integer:=0;
begin
  last_day:=(as_of at time zone 'Asia/Shanghai')::date-1;
  -- ponytail: hourly history scan fits a two-person beta; track last contiguous
  -- settled day if family age makes this measurable.
  for home in select id,(created_at at time zone 'Asia/Shanghai')::date as first_day
      from public.families order by created_at,id loop
    for day_to_bill in select day::date from generate_series(
        home.first_day::timestamp,last_day::timestamp,interval '1 day') day loop
      if not exists(select 1 from public.family_daily_settlements
          where family_id=home.id and business_day=day_to_bill) then
        perform public.settle_family_day(home.id,day_to_bill);
        completed:=completed+1;
      end if;
    end loop;
  end loop;
  return completed;
end; $$;
revoke all on function public.settle_due_family_days(timestamptz)
  from public,anon,authenticated;
select cron.schedule('family-daily-settlement','1 * * * *',
  'select public.settle_due_family_days()');
