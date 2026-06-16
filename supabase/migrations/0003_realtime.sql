-- Household Helper — Realtime
-- Add the tables the mobile client subscribes to into the supabase_realtime
-- publication. Postgres-change events are still filtered by RLS, so members
-- only receive rows for households they belong to.

alter publication supabase_realtime add table public.shopping_list_items;
alter publication supabase_realtime add table public.shops;
alter publication supabase_realtime add table public.catalog_items;

-- REPLICA IDENTITY FULL makes DELETE events include every column (not just the
-- primary key), so client subscriptions filtered by household_id / shop_id still
-- match and receive the delete.
alter table public.shopping_list_items replica identity full;
alter table public.shops replica identity full;
alter table public.catalog_items replica identity full;
