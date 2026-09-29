-- A lost confirmation response must be safe to retry from the local queue.
create or replace function public.sync_task_session(session_id uuid, task_activity text,
  start_at timestamptz, checkpoint_at timestamptz, task_photo_path text,
  is_confirmed boolean) returns jsonb
language plpgsql security definer set search_path='' as $$
declare me uuid:=auth.uid(); previous public.task_sessions; expected_path text;
begin
  if me is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if session_id is null or task_activity is null or task_activity not in ('language','exercise')
    or start_at is null or checkpoint_at is null or is_confirmed is null
    or not isfinite(start_at) or not isfinite(checkpoint_at)
    or checkpoint_at<start_at or checkpoint_at>start_at+interval '6 hours'
    or checkpoint_at>clock_timestamp()+interval '5 minutes' then
    raise exception 'Invalid task interval' using errcode='22023';
  end if;
  expected_path := me::text||'/'||session_id::text;
  if task_photo_path is not null and task_photo_path<>expected_path then
    raise exception 'Invalid photo path' using errcode='22023';
  end if;
  if is_confirmed and task_photo_path is distinct from expected_path then
    raise exception 'Photo required before confirmation' using errcode='22023';
  end if;
  perform 1 from public.wallets where owner_id=me for update;
  if not found then raise exception 'Wallet missing'; end if;
  select * into previous from public.task_sessions where id=session_id;
  if found then
    if previous.owner_id<>me or previous.activity<>task_activity or previous.started_at<>start_at then
      raise exception 'Task identity mismatch' using errcode='42501';
    end if;
    if previous.confirmed then
      if checkpoint_at<>previous.recorded_until or
        (is_confirmed and task_photo_path is distinct from previous.photo_path) then
        raise exception 'Confirmed task is immutable' using errcode='22023';
      end if;
      return public.task_state();
    end if;
    checkpoint_at := greatest(checkpoint_at,previous.recorded_until);
  end if;
  if exists(select 1 from public.task_sessions t where t.owner_id=me and t.id<>session_id
    and t.started_at<checkpoint_at and t.recorded_until>start_at) then
    raise exception 'Overlapping task interval' using errcode='22023';
  end if;
  if is_confirmed and not exists(select 1 from storage.objects
    where bucket_id='task-photos' and name=expected_path) then
    raise exception 'Photo upload is not complete' using errcode='22023';
  end if;
  insert into public.task_sessions(id,owner_id,activity,started_at,recorded_until,photo_path,confirmed)
    values(session_id,me,task_activity,start_at,checkpoint_at,task_photo_path,is_confirmed)
    on conflict(id) do update set recorded_until=excluded.recorded_until,
      photo_path=excluded.photo_path,confirmed=excluded.confirmed;
  if is_confirmed then perform public.settle_tasks_for_owner(me); end if;
  return public.task_state();
end;
$$;
