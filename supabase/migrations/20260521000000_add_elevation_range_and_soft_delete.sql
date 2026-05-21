-- Add elevation_range_m to route_templates so elevation is persisted
-- alongside the route (instead of being recomputed from telemetry, which
-- isn't available for route templates).
ALTER TABLE public.route_templates
  ADD COLUMN IF NOT EXISTS elevation_range_m double precision;
