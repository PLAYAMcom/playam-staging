# PLAYAM Coin Checkout — Staging Test-Mode Setup

This runbook is for configuring the Staging Edge Function only. It does not authorise Production changes or live payments.

## Required Edge Function secrets/settings

Configure these in the Supabase Dashboard for project `PLAYAM-Staging` (`pwnjrdedeoxbmtfywhkk`), under Edge Functions → Secrets:

| Name | Value / requirement |
|---|---|
| `SUPABASE_URL` | Staging project URL |
| `SUPABASE_ANON_KEY` or `SUPABASE_PUBLISHABLE_KEY` | Staging public client key |
| `SUPABASE_SERVICE_ROLE_KEY` | Staging service-role key; keep private |
| `PAYSTACK_SECRET_KEY` | Paystack **test** secret beginning `sk_test_` |
| `PAYSTACK_ENVIRONMENT` | Exactly `test` |
| `PLAYAM_COIN_CHECKOUT_CALLBACK_URL` | `https://playamcom.github.io/` |
| `PLAYAM_COIN_CHECKOUT_ENABLED` | Leave `false` until the other values are verified; set to `true` only for an authorised Staging test |

Never put secret keys in the website, GitHub source, issue comments, or chat. Do not use an `sk_live_` key.

## Built-in safety checks

The deployed `paystack-coin-checkout` function requires a valid signed-in user, obtains price and coin quantity from the server-side active package catalogue, and rejects checkout unless the feature flag is enabled, environment is `test`, and the key begins `sk_test_`. The callback must use HTTPS and the approved `https://playamcom.github.io` origin.

The webhook verifies Paystack signatures and independently verifies transactions with Paystack before it can record a failed payment or credit coins. Coin settlement is performed server-side and is idempotent.

## Safe test sequence

1. Confirm all values above are configured on the Staging project only.
2. Confirm the key is a Paystack test key without copying it into logs or chat.
3. Confirm the feature flag remains off until an authorised test window.
4. Enable the feature flag for the Staging test only.
5. Test one successful sandbox payment, one failed sandbox payment, duplicate webhook delivery, and return to PLAYAM.
6. Verify one coin credit for a successful payment and zero credits for failed/duplicate notifications.
7. Turn the feature flag off after testing.

Do not switch to live credentials or enable Production checkout as part of this runbook.
