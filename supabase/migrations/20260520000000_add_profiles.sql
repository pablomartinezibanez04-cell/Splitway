-- Splitway: User profiles with nickname, avatar, bio, and nickname cooldown.

-- 1. Create profiles table
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nickname text not null,
  avatar_url text,
  bio text,
  nickname_changed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 2. Enable RLS
alter table public.profiles enable row level security;

-- 3. RLS policies — users can read/update only their own profile
create policy "Users can view own profile"
  on public.profiles for select
  using (auth.uid() = id);

create policy "Users can insert own profile"
  on public.profiles for insert
  with check (auth.uid() = id);

create policy "Users can update own profile"
  on public.profiles for update
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- 4. RPC: update nickname with 3-day cooldown enforcement
create or replace function public.update_nickname(new_nickname text)
returns void
language plpgsql
security definer
as $$
declare
  last_change timestamptz;
begin
  select nickname_changed_at into last_change
  from public.profiles
  where id = auth.uid();

  if last_change is not null and (now() - last_change) < interval '3 days' then
    raise exception 'Nickname cooldown active. Wait 3 days between changes.'
      using errcode = 'P0001';
  end if;

  update public.profiles
  set nickname = new_nickname,
      nickname_changed_at = now(),
      updated_at = now()
  where id = auth.uid();
end;
$$;

-- 5. Storage bucket for avatars
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', false)
on conflict (id) do nothing;

-- 6. Storage policies — users can upload/read/delete their own avatars
create policy "Users can upload own avatar"
  on storage.objects for insert
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "Users can read own avatar"
  on storage.objects for select
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "Users can update own avatar"
  on storage.objects for update
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "Users can delete own avatar"
  on storage.objects for delete
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
