# PLAYAM Staging Paystack coin-checkout setup

This runbook is for the isolated Staging project only. It does not authorize Production changes or real-money payments.

## Checkout safety defaults

- Edge Function: `paystack-coin-checkout`.
- Webhook: `paystack-webhook`.
- Checkout feature flag must remain disabled by default:
  `PLAYAM_COIN_CHECKOUT_ENABLED=false`.
- Staging must use Paystack test mode only:
  `PAYSTACK_ENVIRONMENT=test` and a test secret beginning with `sk_test_`.
- Never use a live key in Staging. The checkout function rejects it.
- Do not paste secret values into GitHub, source files, issues, or ChatGPT.

## Required Edge Function secrets

Set these in the Staging Supabase project's Edge Function secrets:

| Name | Required value |
|---|---|
| `PAYSTACK_SECRET_KEY` | Paystack test secret key (`sk_test_...`) |
| `PAYSTACK_ENVIRONMENT` | `test` |
| `PLAYAM_COIN_CHECKOUT_CALLBACK_URL` | `https://playamcom.github.io/game.html` (used by the GitHub Pages app) |
| `PLAYAM_COIN_CHECKOUT_ENABLED` | `false` until an explicitly authorised test window |

The standard Supabase Edge Function environment must also provide `SUPABASE_URL`, `SUPABASE_ANON_KEY` (or `SUPABASE_PUBLISHABLE_KEY`), and `SUPABASE_SERVICE_ROLE_KEY`. These are supplied by the Supabase runtime; never copy the service-role key into browser code.

The checkout function allows only these exact browser origins: `https://playamcom.github.io` and `https://playam-mobile-staging-playam1.vercel.app`. The Vercel mobile app is returned to `https://playam-mobile-staging-playam1.vercel.app/`; the GitHub Pages app uses the callback URL above. Preview deployment URLs and arbitrary origins are not allowed. The Vercel callback is selected server-side from the validated request origin; the browser cannot choose a callback URL.\n\nThe webhook uses the same Staging `PAYSTACK_SECRET_KEY`. Configure the Paystack dashboard webhook URL to the Staging `paystack-webhook` Edge Function URL. Keep the webhook secret and dashboard access private.

## Before enabling a test purchase

1. Confirm the Supabase project is `pwnjrdedeoxbmtfywhkk` (PLAYAM-Staging), not Production.
2. Confirm the key is a Paystack test key without sharing its value.
3. Confirm the GitHub Pages callback is `https://playamcom.github.io/game.html`; the stable Vercel mobile origin must return to its own root URL.
4. Confirm the Paystack dashboard webhook points to the Staging webhook endpoint.
5. Confirm the four active package rows are Starter ₦1,000/10 coins, Standard ₦2,500/25 coins, Popular ₦5,000/50 coins, Premium ₦10,000/100 coins.
6. Obtain explicit owner approval for a controlled test-mode checkout window before changing `PLAYAM_COIN_CHECKOUT_ENABLED` to `true`.
7. Use Paystack test payment details only. Never use a real card or live key.
8. Verify the webhook settles exactly once and the signed-in player's purchased-coin wallet changes by the correct amount.

## Expected checkout behaviour

- The browser sends only `package_code` and an idempotency key.
- The server loads amount and coin quantity from the active database package.
- The browser cannot set the amount or coin quantity.
- The webhook verifies the transaction directly with Paystack before coin credit.
- Duplicate notifications must not create duplicate coin credits.
- A payment still pending after return remains uncredited until verified.
- If initialization has an unknown network outcome, do not create a fresh payment blindly; reconcile the original reference first.

## Stop conditions

Keep checkout disabled and investigate if the callback origin, project ID, environment, key type, payment amount, currency, package snapshot, or webhook verification does not match. Never work around a failed check by weakening authentication, RLS, idempotency, or webhook verification.
