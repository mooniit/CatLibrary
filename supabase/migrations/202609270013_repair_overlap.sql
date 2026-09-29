-- One person's simultaneous study/task timers count only once toward repair.
create or replace function public.repair_window_progress(target_window uuid)
returns bigint language sql stable security definer set search_path='' as $$
  with window_data as (
    select w.starts_at,w.ends_at,e.family_id from public.repair_windows w
      join public.repair_episodes e on e.id=w.episode_id
    where w.id=target_window
  ), ranges as (
    select s.owner_id,s.started_at,s.recorded_until from public.study_sessions s
      join public.family_members m on m.user_id=s.owner_id
      join window_data w on w.family_id=m.family_id
    union all
    select t.owner_id,t.started_at,t.recorded_until from public.task_sessions t
      join public.family_members m on m.user_id=t.owner_id
      join window_data w on w.family_id=m.family_id
  ), clipped as (
    select r.owner_id,tstzrange(
      greatest(r.started_at,w.starts_at),
      least(r.recorded_until,w.ends_at,clock_timestamp()),'[)') as span
    from ranges r cross join window_data w
    where r.started_at<least(w.ends_at,clock_timestamp())
      and r.recorded_until>w.starts_at
  ), merged as (
    select unnest(range_agg(span)) as span from clipped group by owner_id
  )
  select coalesce(sum((extract(epoch from upper(span)-lower(span))*1000)::bigint),0)::bigint
    from merged;
$$;
