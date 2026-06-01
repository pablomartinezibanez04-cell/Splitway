-- supabase/migrations/20260601000003_fix_duplicate_route_text_ids.sql
-- route_templates.id is declared `text` (not uuid). The previous RPC
-- used `uuid` parameter types which forced an implicit text→uuid cast
-- that would throw on any id not in UUID format. Drop and recreate
-- with text params for type-consistency with the column.

drop function if exists public.duplicate_route_as_official(uuid, uuid);

create or replace function public.duplicate_route_as_official(
  p_source_route_id text,
  p_admin_id text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_new_id text := gen_random_uuid()::text;
  v_source record;
begin
  select * into v_source
  from public.route_templates
  where id = p_source_route_id;
  if not found then
    raise exception 'Source route % not found', p_source_route_id
      using errcode = 'P0002';
  end if;

  insert into public.route_templates (
    id, name, description, difficulty, elevation_range_m,
    location_label, owner_id, path_json, start_finish_gate_json,
    thumbnail_url, is_official, created_at, updated_at
  ) values (
    v_new_id,
    'Oficial — ' || v_source.name,
    v_source.description,
    v_source.difficulty,
    v_source.elevation_range_m,
    v_source.location_label,
    p_admin_id::uuid,
    v_source.path_json,
    v_source.start_finish_gate_json,
    v_source.thumbnail_url,
    true,
    now(),
    now()
  );

  insert into public.sectors (id, route_id, label, order_index, gate_json)
  select gen_random_uuid()::text, v_new_id, label, order_index, gate_json
  from public.sectors
  where route_id = p_source_route_id;

  return v_new_id;
end;
$$;

revoke execute on function
  public.duplicate_route_as_official(text, text) from public;
revoke execute on function
  public.duplicate_route_as_official(text, text) from anon;
revoke execute on function
  public.duplicate_route_as_official(text, text) from authenticated;
grant execute on function
  public.duplicate_route_as_official(text, text) to service_role;
