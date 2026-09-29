-- T21: recompute each window from durable checkpoints, including late uploads.
create function public.repair_window_progress(target_window uuid) returns bigint
language sql stable security definer set search_path='' as $$
  with window_data as (
    select w.starts_at,w.ends_at,e.family_id from public.repair_windows w
      join public.repair_episodes e on e.id=w.episode_id
    where w.id=target_window
  ), ranges as (
    select s.started_at,s.recorded_until from public.study_sessions s
      join public.family_members m on m.user_id=s.owner_id
      join window_data w on w.family_id=m.family_id
      where s.started_at<w.ends_at and s.recorded_until>w.starts_at
    union all
    select t.started_at,t.recorded_until from public.task_sessions t
      join public.family_members m on m.user_id=t.owner_id
      join window_data w on w.family_id=m.family_id
      where t.started_at<w.ends_at and t.recorded_until>w.starts_at
  )
  select coalesce(sum(greatest(0,(extract(epoch from
    least(r.recorded_until,w.ends_at,clock_timestamp())
    -greatest(r.started_at,w.starts_at))*1000)::bigint)),0)::bigint
  from ranges r cross join window_data w;
$$;
revoke all on function public.repair_window_progress(uuid)
  from public,anon,authenticated;

create or replace function public.repair_state() returns jsonb
language plpgsql security definer set search_path='' as $$
declare me uuid:=auth.uid(); home uuid; episode public.repair_episodes;
  first_window public.repair_windows; current_window public.repair_windows;
  now_at timestamptz; cycle_number integer; current_cycle integer;
  starts timestamptz; progress bigint;
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
  now_at:=clock_timestamp();
  if episode.status='pending' then
    insert into public.repair_windows
      (episode_id,cycle_no,starts_at,ends_at,status)
      values(episode.id,1,now_at,now_at+interval '72 hours','active')
      returning * into first_window;
    update public.repair_episodes set status='active' where id=episode.id;
  else
    select * into first_window from public.repair_windows
      where episode_id=episode.id and cycle_no=1;
  end if;
  current_cycle:=greatest(1,
    floor(extract(epoch from now_at-first_window.starts_at)/259200)::integer+1);
  for cycle_number in 1..current_cycle loop
    starts:=first_window.starts_at+(cycle_number-1)*interval '72 hours';
    insert into public.repair_windows
      (episode_id,cycle_no,starts_at,ends_at,status)
      values(episode.id,cycle_number,starts,starts+interval '72 hours','active')
      on conflict(episode_id,cycle_no) do nothing;
    select * into current_window from public.repair_windows
      where episode_id=episode.id and cycle_no=cycle_number;
    progress:=public.repair_window_progress(current_window.id);
    if progress>=7200000 then
      update public.repair_windows set progress_ms=progress,status='completed'
        where id=current_window.id;
      update public.repair_episodes set status='completed',completed_at=now_at,
        grace_through=(now_at at time zone 'Asia/Shanghai')::date+1
        where id=episode.id;
      return jsonb_build_object('status','completed','episode_id',episode.id,
        'window_id',current_window.id,'cycle_no',cycle_number,
        'progress_ms',progress,'target_ms',7200000,
        'grace_through',(now_at at time zone 'Asia/Shanghai')::date+1);
    end if;
    update public.repair_windows set progress_ms=progress,
      status=case when ends_at<=now_at then 'failed' else 'active' end
      where id=current_window.id;
  end loop;
  return jsonb_build_object('status','active','episode_id',episode.id,
    'window_id',current_window.id,'cycle_no',current_cycle,
    'starts_at',current_window.starts_at,'ends_at',current_window.ends_at,
    'progress_ms',progress,'target_ms',7200000);
end; $$;
