alter table public.route_templates
  add column if not exists location_label text;
