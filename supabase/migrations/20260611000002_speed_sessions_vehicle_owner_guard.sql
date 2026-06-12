-- Enforce vehicle ownership on speed_sessions (audit BUG-13).
--
-- The FK speed_sessions.vehicle_id -> vehicles.id only checks existence, not
-- that the vehicle belongs to the same user. A client could therefore attach
-- its session to another user's vehicle id. This BEFORE INSERT/UPDATE trigger
-- rejects any vehicle_id that does not belong to the row's user_id.
--
-- SECURITY DEFINER so the check can read public.vehicles regardless of the
-- caller's RLS view (the row being inserted is the caller's own).

create or replace function public.enforce_speed_session_vehicle_owner()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.vehicle_id is not null then
    if not exists (
      select 1 from public.vehicles v
      where v.id = new.vehicle_id
        and v.user_id = new.user_id
    ) then
      raise exception
        'vehicle % does not belong to user %', new.vehicle_id, new.user_id
        using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

revoke execute on function public.enforce_speed_session_vehicle_owner()
  from public, anon, authenticated;

drop trigger if exists enforce_speed_session_vehicle_owner_trg
  on public.speed_sessions;
create trigger enforce_speed_session_vehicle_owner_trg
  before insert or update on public.speed_sessions
  for each row execute function public.enforce_speed_session_vehicle_owner();
