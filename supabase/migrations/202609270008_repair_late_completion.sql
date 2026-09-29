-- A late upload may complete an earlier window after later windows were opened.
alter table public.repair_windows drop constraint repair_windows_status_check;
alter table public.repair_windows add constraint repair_windows_status_check
  check(status in ('active','failed','completed','superseded'));

create function public.supersede_repair_windows() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if new.status='completed' and old.status<>'completed' then
    update public.repair_windows set status='superseded'
      where episode_id=new.id and status='active';
  end if;
  return new;
end; $$;
revoke all on function public.supersede_repair_windows()
  from public,anon,authenticated;
create trigger repair_completion_supersedes_later
  after update of status on public.repair_episodes
  for each row execute function public.supersede_repair_windows();
