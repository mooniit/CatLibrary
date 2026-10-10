-- Read-only original study evidence for the unified learning history.
create function public.study_history() returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'owner_id',s.owner_id,
  'run_id',s.run_id,'started_at',s.started_at,'recorded_until',s.recorded_until,
  'confirmed',s.confirmed,'activity','study') order by s.started_at desc,s.id),'[]'::jsonb)
  from public.study_sessions s where s.owner_id=auth.uid());
end $$;
revoke all on function public.study_history() from public,anon;
grant execute on function public.study_history() to authenticated;
