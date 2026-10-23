-- Get Saucy vendor locator: run in a Supabase project's SQL editor.
create extension if not exists pgcrypto;
create table if not exists public.vendor_locations (
  user_id uuid primary key references auth.users(id) on delete cascade,
  business_name text not null check (char_length(business_name) between 2 and 100),
  description text not null default '',
  phone text not null default '',
  serving_address text not null default '',
  latitude double precision check(latitude between -90 and 90),
  longitude double precision check(longitude between -180 and 180),
  is_open boolean not null default false,
  updated_at timestamptz not null default now(),
  constraint open_needs_location check (not is_open or (latitude is not null and longitude is not null))
);
alter table public.vendor_locations enable row level security;
drop policy if exists "Public can read open vendor locations" on public.vendor_locations;
create policy "Public can read open vendor locations" on public.vendor_locations for select using (is_open = true or auth.uid() = user_id);
drop policy if exists "Vendors can insert their own listing" on public.vendor_locations;
create policy "Vendors can insert their own listing" on public.vendor_locations for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists "Vendors can update their own listing" on public.vendor_locations;
create policy "Vendors can update their own listing" on public.vendor_locations for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "Vendors can delete their own listing" on public.vendor_locations;
create policy "Vendors can delete their own listing" on public.vendor_locations for delete to authenticated using (auth.uid() = user_id);
create index if not exists vendor_locations_open_idx on public.vendor_locations (is_open) where is_open = true;
-- Enable email authentication in Supabase Authentication settings.
-- Never expose a service_role key in the public website.
