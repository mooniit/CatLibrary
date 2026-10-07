-- Explicit provenance for authorized, individually scoped test grants.
-- No startup grant, public granting RPC or economic balance change.
alter table public.furniture_inventory drop constraint furniture_inventory_source_check;
alter table public.furniture_inventory add constraint furniture_inventory_source_check
  check(source in ('purchase','initial','souvenir','test_grant'));
