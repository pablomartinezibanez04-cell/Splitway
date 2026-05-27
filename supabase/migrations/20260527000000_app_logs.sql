-- App diagnostic logs uploaded from the mobile client.
create table if not exists public.app_logs (
  id           uuid primary key,
  timestamp    timestamptz not null,
  level        text not null check (level in ('debug','info','warning','error')),
  tag          text not null,
  message      text not null,
  error        text,
  stack_trace  text,
  context      jsonb,
  app_version  text not null,
  platform     text not null,
  device_model text not null,
  user_id      uuid references auth.users(id) on delete set null
);

create index if not exists idx_app_logs_user_ts on public.app_logs (user_id, timestamp desc);
create index if not exists idx_app_logs_level_ts on public.app_logs (level, timestamp desc);

alter table public.app_logs enable row level security;

-- Anyone authenticated can insert their own logs (or anonymous pre-login logs).
drop policy if exists "app_logs_insert_own" on public.app_logs;
create policy "app_logs_insert_own"
  on public.app_logs
  for insert
  to authenticated
  with check (user_id = auth.uid() or user_id is null);

-- Reading is restricted to service_role (we inspect logs via the dashboard).
drop policy if exists "app_logs_select_service" on public.app_logs;
create policy "app_logs_select_service"
  on public.app_logs
  for select
  to service_role
  using (true);

-- Daily purge of logs older than 30 days. Requires pg_cron to be enabled in
-- the project; the unschedule guards against duplicate jobs on re-runs.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if exists (select 1 from cron.job where jobname = 'purge_app_logs') then
      perform cron.unschedule('purge_app_logs');
    end if;
    perform cron.schedule(
      'purge_app_logs',
      '0 3 * * *',
      $job$delete from public.app_logs where timestamp < now() - interval '30 days'$job$
    );
  end if;
end
$$;
