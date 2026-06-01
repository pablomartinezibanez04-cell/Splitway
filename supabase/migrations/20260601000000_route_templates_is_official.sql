-- supabase/migrations/20260601000000_route_templates_is_official.sql
-- Mark a route as "official" — curated by the admin team and visible
-- to every Flutter user (the visibility wiring is a separate follow-up
-- Flutter PR, this migration is only the schema change).

alter table public.route_templates
  add column if not exists is_official boolean not null default false;

-- Partial index: official routes are the minority, so a partial index
-- keeps the bulk of the table out of the index entirely.
create index if not exists route_templates_is_official_idx
  on public.route_templates (is_official)
  where is_official = true;
