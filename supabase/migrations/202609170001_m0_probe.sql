-- M0 isolated probe, not the production family or wallet schema.
create table public.m0_probe_notes (
  owner_id uuid primary key references auth.users(id) on delete cascade,
  note text not null check (length(note) <= 200)
);
alter table public.m0_probe_notes enable row level security;
revoke all on public.m0_probe_notes from anon;
grant select, insert, update, delete on public.m0_probe_notes to authenticated;
create policy m0_own_notes on public.m0_probe_notes for all to authenticated
  using ((select auth.uid()) = owner_id) with check ((select auth.uid()) = owner_id);
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('m0-probe-private', 'm0-probe-private', false, 1048576, array['image/png','image/jpeg']);
create policy m0_own_files on storage.objects for all to authenticated
  using (bucket_id = 'm0-probe-private' and (storage.foldername(name))[1] = (select auth.uid())::text)
  with check (bucket_id = 'm0-probe-private' and (storage.foldername(name))[1] = (select auth.uid())::text);
