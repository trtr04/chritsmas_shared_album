-- Seaside Villa · shared Christmas album
-- One shared password lets friends view, add, rename and delete photos.
-- Everything is enforced here in the database (Row Level Security),
-- not in the web page, so the public "anon" key in the page is safe.
--
-- After this runs, set the password ONCE in the Supabase SQL editor:
--   select private.set_album_password('your album password');
-- (Never commit the real password to this repo.)

create extension if not exists pgcrypto with schema extensions;

-- ---------- private schema (not exposed through the Data API) ----------
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated;   -- needed so RLS policies can call private.is_member()

create table if not exists private.album_settings (
  id            int primary key default 1 check (id = 1),
  password_hash text
);
insert into private.album_settings (id) values (1) on conflict do nothing;

create table if not exists private.join_attempts (
  user_id uuid,
  at      timestamptz not null default now()
);
revoke all on private.album_settings, private.join_attempts from public, anon, authenticated;

-- ---------- public tables ----------
create table if not exists public.members (
  user_id      uuid primary key references auth.users (id) on delete cascade,
  display_name text not null default 'friend' check (char_length(display_name) <= 40),
  joined_at    timestamptz not null default now()
);
alter table public.members enable row level security;

create table if not exists public.photos (
  id            uuid primary key default gen_random_uuid(),
  path          text not null unique,               -- full-size image in the "photos" bucket; thumbnail at thumbs/<path>
  caption       text not null default 'untitled' check (char_length(caption) <= 60),
  added_by      uuid default auth.uid() references auth.users (id) on delete set null,
  added_by_name text check (char_length(added_by_name) <= 40),
  created_at    timestamptz not null default now()
);
alter table public.photos enable row level security;

-- ---------- helper functions ----------
create or replace function private.is_member()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.members where user_id = auth.uid());
$$;
revoke all on function private.is_member() from public, anon;
grant execute on function private.is_member() to authenticated;

-- Run by you in the SQL editor to set or change the password.
create or replace function private.set_album_password(new_password text)
returns void language sql security definer set search_path = '' as $$
  update private.album_settings
     set password_hash = extensions.crypt(new_password, extensions.gen_salt('bf'))
   where id = 1;
$$;
revoke all on function private.set_album_password(text) from public, anon, authenticated;

-- Called by the page: checks the password and, if right, adds this browser as a member.
create or replace function public.join_album(passcode text, display_name text default 'friend')
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  h      text;
  mine   int;
  recent int;
begin
  if auth.uid() is null then
    raise exception 'not signed in';
  end if;

  -- slow down password guessing
  select count(*) into mine   from private.join_attempts where user_id = auth.uid() and at > now() - interval '10 minutes';
  select count(*) into recent from private.join_attempts where at > now() - interval '1 minute';
  if mine >= 8 or recent >= 40 then
    raise exception 'too many tries, please wait a few minutes';
  end if;

  select password_hash into h from private.album_settings where id = 1;
  if h is null or extensions.crypt(passcode, h) <> h then
    insert into private.join_attempts (user_id) values (auth.uid());
    return false;
  end if;

  insert into public.members (user_id, display_name)
  values (auth.uid(), left(coalesce(nullif(trim(display_name), ''), 'friend'), 40))
  on conflict (user_id) do update set display_name = excluded.display_name;
  return true;
end $$;
revoke all on function public.join_album(text, text) from public, anon;
grant execute on function public.join_album(text, text) to authenticated;

-- ---------- table access (members only) ----------
grant select on public.members to authenticated;
create policy "see own membership" on public.members
  for select to authenticated using (user_id = auth.uid());

grant select, insert, delete on public.photos to authenticated;
grant update (caption) on public.photos to authenticated;      -- only the caption can be edited

create policy "members view photos" on public.photos
  for select to authenticated using (private.is_member());
create policy "members add photos" on public.photos
  for insert to authenticated with check (private.is_member() and added_by = auth.uid());
create policy "members rename photos" on public.photos
  for update to authenticated using (private.is_member()) with check (private.is_member());
create policy "members delete photos" on public.photos
  for delete to authenticated using (private.is_member());

-- ---------- storage: private bucket, members only ----------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('photos', 'photos', false, 10485760, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

create policy "members read album files" on storage.objects
  for select to authenticated using (bucket_id = 'photos' and private.is_member());
create policy "members upload album files" on storage.objects
  for insert to authenticated with check (bucket_id = 'photos' and private.is_member());
create policy "members delete album files" on storage.objects
  for delete to authenticated using (bucket_id = 'photos' and private.is_member());

-- ---------- live updates ----------
alter publication supabase_realtime add table public.photos;
