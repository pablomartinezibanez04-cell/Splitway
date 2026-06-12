-- Per-user rate limiting for the mapbox-routing edge function (audit SEC-1).
--
-- The edge function proxies the PAID Mapbox Map Matching API using a secret
-- server token. Previously it only checked that an Authorization header was
-- present (never validated it) and had no rate limit, so any holder of the
-- public anon key could run up the bill. The function now validates the JWT
-- AND calls consume_mapbox_quota() with the authenticated user id; this table
-- + RPC implement an atomic fixed-window counter.

create table if not exists public.mapbox_quota (
  user_id      uuid primary key references auth.users(id) on delete cascade,
  window_start timestamptz not null default now(),
  count        integer not null default 0
);

-- Service-role only: the edge function (service-role client) is the sole
-- caller. RLS on with no policies => no access for anon/authenticated.
alter table public.mapbox_quota enable row level security;

-- Atomically record one request for p_user_id and return whether it is within
-- the allowance. Fixed window of p_window_seconds: the window resets the first
-- time a request lands after it has elapsed.
create or replace function public.consume_mapbox_quota(
  p_user_id uuid,
  p_max integer,
  p_window_seconds integer
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now   timestamptz := now();
  v_count integer;
begin
  insert into public.mapbox_quota (user_id, window_start, count)
  values (p_user_id, v_now, 1)
  on conflict (user_id) do update set
    window_start = case
      when public.mapbox_quota.window_start
           < v_now - make_interval(secs => p_window_seconds)
      then v_now
      else public.mapbox_quota.window_start
    end,
    count = case
      when public.mapbox_quota.window_start
           < v_now - make_interval(secs => p_window_seconds)
      then 1
      else public.mapbox_quota.count + 1
    end
  returning count into v_count;

  return v_count <= p_max;
end;
$$;

revoke execute on function
  public.consume_mapbox_quota(uuid, integer, integer) from public, anon, authenticated;
grant execute on function
  public.consume_mapbox_quota(uuid, integer, integer) to service_role;
