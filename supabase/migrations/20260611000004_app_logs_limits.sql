-- Bound and throttle client-submitted diagnostic logs (audit SEC-2).
--
-- The app_logs INSERT policy lets any authenticated user write arbitrary log
-- content with no size or frequency limit (the 10/s cap lives only in the
-- Flutter client and is trivially bypassed). This adds:
--   1. Length CHECK constraints so a single row can't be inflated to MBs.
--   2. A per-user fixed-window insert throttle, keyed on auth.uid() (so it
--      can't be dodged by inserting rows with user_id = null).

-- 1. Size guards. NOT VALID: enforced for new rows without re-validating the
-- (already well-formed) historical rows.
alter table public.app_logs
  add constraint app_logs_message_len      check (length(message) <= 10000) not valid,
  add constraint app_logs_error_len        check (error is null or length(error) <= 10000) not valid,
  add constraint app_logs_stack_len        check (stack_trace is null or length(stack_trace) <= 20000) not valid,
  add constraint app_logs_tag_len          check (length(tag) <= 100) not valid,
  add constraint app_logs_app_version_len  check (length(app_version) <= 50) not valid,
  add constraint app_logs_platform_len     check (length(platform) <= 50) not valid,
  add constraint app_logs_device_model_len check (length(device_model) <= 200) not valid,
  add constraint app_logs_context_size     check (context is null or octet_length(context::text) <= 50000) not valid;

-- 2. Per-user insert throttle.
create table if not exists public.app_logs_rate (
  user_id      uuid primary key references auth.users(id) on delete cascade,
  window_start timestamptz not null default now(),
  count        integer not null default 0
);
alter table public.app_logs_rate enable row level security; -- service/internal only

create or replace function public.enforce_app_logs_rate()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_now   timestamptz := now();
  v_count integer;
  v_max   constant integer := 2000;  -- inserts per minute per user
begin
  -- service_role / internal inserts (no JWT) are not throttled.
  if v_uid is null then
    return new;
  end if;

  insert into public.app_logs_rate (user_id, window_start, count)
  values (v_uid, v_now, 1)
  on conflict (user_id) do update set
    window_start = case
      when public.app_logs_rate.window_start < v_now - interval '1 minute'
      then v_now else public.app_logs_rate.window_start end,
    count = case
      when public.app_logs_rate.window_start < v_now - interval '1 minute'
      then 1 else public.app_logs_rate.count + 1 end
  returning count into v_count;

  if v_count > v_max then
    raise exception 'app_logs insert rate limit exceeded'
      using errcode = '53400';
  end if;

  return new;
end;
$$;

revoke execute on function public.enforce_app_logs_rate()
  from public, anon, authenticated;

drop trigger if exists enforce_app_logs_rate_trg on public.app_logs;
create trigger enforce_app_logs_rate_trg
  before insert on public.app_logs
  for each row execute function public.enforce_app_logs_rate();
