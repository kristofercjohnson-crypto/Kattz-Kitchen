-- Run in Supabase SQL Editor before testing food-spots.html.
-- Business accounts only; one favorite and one editable review per member/business.
create table if not exists public.favorite_food_spots (
 user_id uuid not null references public.profiles(user_id) on delete cascade,
 business_id uuid not null references public.profiles(user_id) on delete cascade,
 created_at timestamptz not null default now(),
 primary key(user_id,business_id),
 constraint no_self_favorite check(user_id<>business_id)
);
create table if not exists public.food_spot_reviews (
 user_id uuid not null references public.profiles(user_id) on delete cascade,
 business_id uuid not null references public.profiles(user_id) on delete cascade,
 stars integer not null check(stars between 1 and 5),
 body text not null check(char_length(trim(body)) between 1 and 1500),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 primary key(user_id,business_id),
 constraint no_self_review check(user_id<>business_id)
);
-- Prevent targeting personal creators, even through direct API calls.
create or replace function public.require_food_business()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 if not exists(select 1 from public.profiles where user_id=new.business_id and account_type='business') then
  raise exception 'Only food business profiles can be favorited or reviewed';
 end if;
 return new;
end $$;
drop trigger if exists favorite_business_only on public.favorite_food_spots;
create trigger favorite_business_only before insert or update on public.favorite_food_spots
for each row execute function public.require_food_business();
drop trigger if exists review_business_only on public.food_spot_reviews;
create trigger review_business_only before insert or update on public.food_spot_reviews
for each row execute function public.require_food_business();
alter table public.favorite_food_spots enable row level security;
alter table public.food_spot_reviews enable row level security;
drop policy if exists "Read own favorites" on public.favorite_food_spots;
create policy "Read own favorites" on public.favorite_food_spots for select to authenticated using(auth.uid()=user_id);
drop policy if exists "Save own favorites" on public.favorite_food_spots;
create policy "Save own favorites" on public.favorite_food_spots for insert to authenticated with check(auth.uid()=user_id);
drop policy if exists "Remove own favorites" on public.favorite_food_spots;
create policy "Remove own favorites" on public.favorite_food_spots for delete to authenticated using(auth.uid()=user_id);
drop policy if exists "Read public reviews" on public.food_spot_reviews;
create policy "Read public reviews" on public.food_spot_reviews for select using(true);
drop policy if exists "Write own reviews" on public.food_spot_reviews;
create policy "Write own reviews" on public.food_spot_reviews for insert to authenticated with check(auth.uid()=user_id);
drop policy if exists "Edit own reviews" on public.food_spot_reviews;
create policy "Edit own reviews" on public.food_spot_reviews for update to authenticated using(auth.uid()=user_id) with check(auth.uid()=user_id);
drop policy if exists "Delete own reviews" on public.food_spot_reviews;
create policy "Delete own reviews" on public.food_spot_reviews for delete to authenticated using(auth.uid()=user_id);
grant select,insert,delete on public.favorite_food_spots to authenticated;
grant select on public.food_spot_reviews to anon,authenticated;
grant insert,update,delete on public.food_spot_reviews to authenticated;
