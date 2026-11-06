-- Get Saucy VIP subscriptions. Run after supabase-community-setup.sql.
create table if not exists public.user_subscriptions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  stripe_customer_id text unique,
  stripe_subscription_id text unique,
  price_id text,
  status text not null default 'inactive'
    check (status in ('inactive','incomplete','incomplete_expired','trialing','active','past_due','canceled','unpaid','paused')),
  current_period_end timestamptz,
  cancel_at_period_end boolean not null default false,
  updated_at timestamptz not null default now()
);
alter table public.user_subscriptions enable row level security;
revoke all on public.user_subscriptions from anon, authenticated;
grant select on public.user_subscriptions to authenticated;
grant select, insert, update, delete on public.user_subscriptions to service_role;
drop policy if exists "Members read their own VIP status" on public.user_subscriptions;
create policy "Members read their own VIP status"
  on public.user_subscriptions for select to authenticated
  using (auth.uid() = user_id);
create index if not exists user_subscriptions_status_idx
  on public.user_subscriptions(status);
