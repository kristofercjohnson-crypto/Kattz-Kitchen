-- Get Saucy community: run once in Supabase SQL Editor.
-- This sets up public profiles, photo/video/recipe posts, comments, emoji reactions,
-- content reports, and a public media bucket with owner-only uploads/deletes.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  account_type text not null default 'personal' check (account_type in ('personal','business')),
  display_name text not null default 'Get Saucy member' check (char_length(display_name) between 1 and 80),
  city text not null default '' check (char_length(city) <= 120),
  bio text not null default '' check (char_length(bio) <= 500),
  cuisine_background text not null default '' check (char_length(cuisine_background) <= 120),
  business_name text not null default '' check (char_length(business_name) <= 100),
  business_category text not null default '' check (char_length(business_category) <= 80),
  phone text not null default '' check (char_length(phone) <= 30),
  website text not null default '' check (char_length(website) <= 250),
  menu_or_social_url text not null default '' check (char_length(menu_or_social_url) <= 250),
  business_description text not null default '' check (char_length(business_description) <= 500),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.profiles enable row level security;
drop policy if exists "Profiles are public" on public.profiles;
create policy "Profiles are public" on public.profiles for select using (true);
drop policy if exists "Users create own profile" on public.profiles;
create policy "Users create own profile" on public.profiles for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists "Users update own profile" on public.profiles;
create policy "Users update own profile" on public.profiles for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
grant select on public.profiles to anon, authenticated;
grant insert, update on public.profiles to authenticated;

create or replace function public.get_saucy_new_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare m jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
begin
  insert into public.profiles (
    user_id, account_type, display_name, city, bio, cuisine_background,
    business_name, business_category, phone, website, menu_or_social_url, business_description
  ) values (
    new.id,
    case when m->>'account_type' = 'business' then 'business' else 'personal' end,
    coalesce(nullif(m->>'display_name',''), nullif(m->>'business_name',''), 'Get Saucy member'),
    coalesce(m->>'city',''),
    coalesce(m->>'bio',''),
    coalesce(m->>'cuisine_background',''),
    coalesce(m->>'business_name',''),
    coalesce(m->>'business_category',''),
    coalesce(m->>'phone',''),
    coalesce(m->>'website',''),
    coalesce(m->>'menu_or_social_url',''),
    coalesce(m->>'business_description','')
  ) on conflict (user_id) do nothing;
  return new;
end;
$$;
drop trigger if exists get_saucy_auth_profile on auth.users;
create trigger get_saucy_auth_profile after insert on auth.users
for each row execute function public.get_saucy_new_profile();

-- Backfill accounts created before this setup is run.
insert into public.profiles (
  user_id, account_type, display_name, city, bio, cuisine_background,
  business_name, business_category, phone, website, menu_or_social_url, business_description
)
select
  u.id,
  case when u.raw_user_meta_data->>'account_type' = 'business' then 'business' else 'personal' end,
  coalesce(nullif(u.raw_user_meta_data->>'display_name',''), nullif(u.raw_user_meta_data->>'business_name',''), 'Get Saucy member'),
  coalesce(u.raw_user_meta_data->>'city',''),
  coalesce(u.raw_user_meta_data->>'bio',''),
  coalesce(u.raw_user_meta_data->>'cuisine_background',''),
  coalesce(u.raw_user_meta_data->>'business_name',''),
  coalesce(u.raw_user_meta_data->>'business_category',''),
  coalesce(u.raw_user_meta_data->>'phone',''),
  coalesce(u.raw_user_meta_data->>'website',''),
  coalesce(u.raw_user_meta_data->>'menu_or_social_url',''),
  coalesce(u.raw_user_meta_data->>'business_description','')
from auth.users u
on conflict (user_id) do nothing;

create table if not exists public.posts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(user_id) on delete cascade,
  post_type text not null default 'food' check (post_type in ('food','recipe')),
  media_type text not null check (media_type in ('image','video','none')),
  media_path text not null default '',
  title text not null default '' check (char_length(title) <= 120),
  caption text not null default '' check (char_length(caption) <= 2000),
  ingredients text not null default '' check (char_length(ingredients) <= 5000),
  instructions text not null default '' check (char_length(instructions) <= 10000),
  created_at timestamptz not null default now(),
  constraint post_has_content check (
    char_length(trim(caption)) > 0 or char_length(trim(title)) > 0 or media_path <> ''
  ),
  constraint media_path_matches_type check (
    (media_type = 'none' and media_path = '') or (media_type in ('image','video') and media_path <> '')
  )
);
create index if not exists posts_created_at_idx on public.posts (created_at desc);
create index if not exists posts_user_id_idx on public.posts (user_id);
alter table public.posts enable row level security;
drop policy if exists "Posts are public" on public.posts;
create policy "Posts are public" on public.posts for select using (true);
drop policy if exists "Signed-in users create own posts" on public.posts;
create policy "Signed-in users create own posts" on public.posts for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists "Users update own posts" on public.posts;
create policy "Users update own posts" on public.posts for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "Users delete own posts" on public.posts;
create policy "Users delete own posts" on public.posts for delete to authenticated using (auth.uid() = user_id);
grant select on public.posts to anon, authenticated;
grant insert, update, delete on public.posts to authenticated;

create table if not exists public.comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references public.profiles(user_id) on delete cascade,
  body text not null check (char_length(trim(body)) between 1 and 1000),
  created_at timestamptz not null default now()
);
create index if not exists comments_post_created_idx on public.comments (post_id, created_at);
alter table public.comments enable row level security;
drop policy if exists "Comments are public" on public.comments;
create policy "Comments are public" on public.comments for select using (true);
drop policy if exists "Signed-in users add comments" on public.comments;
create policy "Signed-in users add comments" on public.comments for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists "Users edit own comments" on public.comments;
create policy "Users edit own comments" on public.comments for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "Users delete own comments" on public.comments;
create policy "Users delete own comments" on public.comments for delete to authenticated using (auth.uid() = user_id);
grant select on public.comments to anon, authenticated;
grant insert, update, delete on public.comments to authenticated;

create table if not exists public.post_reactions (
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references public.profiles(user_id) on delete cascade,
  emoji text not null check (emoji in ('❤️','😋','🔥','👏','😂')),
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);
create index if not exists post_reactions_post_idx on public.post_reactions (post_id);
alter table public.post_reactions enable row level security;
drop policy if exists "Reactions are public" on public.post_reactions;
create policy "Reactions are public" on public.post_reactions for select using (true);
drop policy if exists "Users react as themselves" on public.post_reactions;
create policy "Users react as themselves" on public.post_reactions for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists "Users change own reaction" on public.post_reactions;
create policy "Users change own reaction" on public.post_reactions for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "Users remove own reaction" on public.post_reactions;
create policy "Users remove own reaction" on public.post_reactions for delete to authenticated using (auth.uid() = user_id);
grant select on public.post_reactions to anon, authenticated;
grant insert, update, delete on public.post_reactions to authenticated;

create table if not exists public.post_reports (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  reporter_id uuid not null references public.profiles(user_id) on delete cascade,
  reason text not null check (char_length(trim(reason)) between 2 and 300),
  created_at timestamptz not null default now(),
  unique (post_id, reporter_id)
);
alter table public.post_reports enable row level security;
drop policy if exists "Signed-in users report posts" on public.post_reports;
create policy "Signed-in users report posts" on public.post_reports for insert to authenticated with check (auth.uid() = reporter_id);
grant insert on public.post_reports to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('get-saucy-posts','get-saucy-posts',true,52428800,
  array['image/jpeg','image/png','image/webp','image/gif','video/mp4','video/webm','video/quicktime'])
on conflict (id) do update set public = true, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;
drop policy if exists "Anyone can view Get Saucy post media" on storage.objects;
create policy "Anyone can view Get Saucy post media" on storage.objects for select using (bucket_id = 'get-saucy-posts');
drop policy if exists "Users upload to own Get Saucy folder" on storage.objects;
create policy "Users upload to own Get Saucy folder" on storage.objects for insert to authenticated
with check (bucket_id = 'get-saucy-posts' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "Users update own Get Saucy media" on storage.objects;
create policy "Users update own Get Saucy media" on storage.objects for update to authenticated
using (bucket_id = 'get-saucy-posts' and (storage.foldername(name))[1] = auth.uid()::text)
with check (bucket_id = 'get-saucy-posts' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "Users delete own Get Saucy media" on storage.objects;
create policy "Users delete own Get Saucy media" on storage.objects for delete to authenticated
using (bucket_id = 'get-saucy-posts' and (storage.foldername(name))[1] = auth.uid()::text);

-- Video duration is enforced in the browser for the free launch experience (maximum 15 seconds).
-- VIP videos up to 10 minutes should be enabled only after subscription verification is implemented.
-- The publishable Supabase key is safe for browser use; never place a service-role key in this website.


-- Moderation workflow. Roles are read from Supabase app_metadata, which clients cannot edit.
alter table public.posts
  add column if not exists status text not null default 'published'
    check (status in ('published','hidden','removed')),
  add column if not exists moderated_at timestamptz,
  add column if not exists moderated_by uuid references auth.users(id) on delete set null,
  add column if not exists moderation_note text not null default '';

alter table public.post_reports
  add column if not exists status text not null default 'pending'
    check (status in ('pending','reviewed','dismissed')),
  add column if not exists reviewed_at timestamptz,
  add column if not exists reviewed_by uuid references auth.users(id) on delete set null,
  add column if not exists resolution text not null default '';

create index if not exists posts_moderation_status_idx on public.posts (status, created_at desc);
create index if not exists post_reports_pending_idx on public.post_reports (status, created_at desc);

-- Public visitors see published posts. Authors can still view their own posts.
-- Trusted moderators can view and act on all posts.
drop policy if exists "Posts are public" on public.posts;
create policy "Published posts and authorized review" on public.posts
for select using (
  status = 'published'
  or auth.uid() = user_id
  or coalesce(auth.jwt()->'app_metadata'->>'role','') in ('moderator','admin')
);
drop policy if exists "Users update own posts" on public.posts;
create policy "Authors and moderators update posts" on public.posts
for update to authenticated
using (
  auth.uid() = user_id
  or coalesce(auth.jwt()->'app_metadata'->>'role','') in ('moderator','admin')
)
with check (
  auth.uid() = user_id
  or coalesce(auth.jwt()->'app_metadata'->>'role','') in ('moderator','admin')
);

drop policy if exists "Moderators read reports" on public.post_reports;
create policy "Moderators read reports" on public.post_reports
for select to authenticated
using (coalesce(auth.jwt()->'app_metadata'->>'role','') in ('moderator','admin'));
drop policy if exists "Moderators update reports" on public.post_reports;
create policy "Moderators update reports" on public.post_reports
for update to authenticated
using (coalesce(auth.jwt()->'app_metadata'->>'role','') in ('moderator','admin'))
with check (coalesce(auth.jwt()->'app_metadata'->>'role','') in ('moderator','admin'));
grant select, update on public.post_reports to authenticated;

-- Grant moderator access only to trusted accounts. Replace the placeholder and
-- run this separately in the Supabase SQL Editor; never use user_metadata for roles.
-- update auth.users
-- set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) || '{"role":"moderator"}'::jsonb
-- where email = 'YOUR_TRUSTED_SIGN_IN_EMAIL';
