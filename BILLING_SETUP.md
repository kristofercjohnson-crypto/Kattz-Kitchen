# Get Saucy VIP billing setup

The website code is prepared for a recurring $4.99 USD monthly VIP membership. It does not accept charges until Stripe and Supabase are configured. Keep Stripe in test mode until the flow has been verified.

## 1. Create the membership table

In Supabase, open SQL Editor and run supabase-vip-billing-setup.sql after the community setup. Members can read only their own subscription status; the server-side webhook writes the records.

## 2. Create the Stripe test price

In Stripe Dashboard test mode, create a product named Get Saucy VIP and a recurring price of $4.99 USD per month. Copy its price ID. Checkout checks the configured price is exactly $4.99 USD monthly before it creates a session.

Enable Stripe Customer Portal and allow members to cancel subscriptions and update payment methods.

## 3. Save secrets in Supabase

In Supabase Dashboard, open Edge Function Secrets. Save these values there; do not put secret keys in website code or GitHub.

- STRIPE_SECRET_KEY: Stripe test-mode secret key
- STRIPE_VIP_PRICE_ID: the test-mode $4.99 monthly price ID
- STRIPE_WEBHOOK_SECRET: the signing secret from step 5
- SITE_URL: https://get-saucy.vercel.app

Supabase supplies its project URL and server-side service key to deployed Edge Functions. Never put a service-role key in the browser.

## 4. Deploy the Edge Function

From the repository root, install and authenticate the Supabase CLI, then deploy function vip-billing to project tacvlueakxokrzvtxpnx. The Supabase config disables gateway JWT verification for this function because it handles both Stripe webhooks and signed-in member actions. Member actions validate the Supabase user token directly; webhook requests must pass Stripe signature verification.

## 5. Add the Stripe webhook

In Stripe Dashboard test mode, create an endpoint at:

https://tacvlueakxokrzvtxpnx.supabase.co/functions/v1/vip-billing

Select these events:

- checkout.session.completed
- customer.subscription.created
- customer.subscription.updated
- customer.subscription.deleted
- invoice.payment_failed

Copy the endpoint signing secret into Supabase as STRIPE_WEBHOOK_SECRET.

## 6. Test before enabling live charges

Open Get Saucy, sign in, and join VIP. Confirm checkout shows $4.99 monthly, returns to the community page, and unlocks 10-minute videos after the webhook confirms the subscription. Use Manage VIP billing to test cancellation and payment-method updates.

Only after test mode works, create the matching $4.99 price in Stripe live mode and replace the test secret, price ID, and webhook signing secret with live-mode values in Supabase. Never send those secrets in chat.

Until those dashboard steps are complete, VIP stays disabled and the free community remains available.