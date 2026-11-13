# PLAYAM Staging

This repository is the isolated browser app for PLAYAM Staging. It is not the Production site.

## Safety boundaries

- Browser app must use Supabase project `pwnjrdedeoxbmtfywhkk`.
- Production project `erjxmesxmmmaxivvmbsi` must never appear in this repository.
- Only a Supabase publishable key belongs in browser code. Never commit service-role keys, secret API keys, passwords, or webhook secrets.
- Keep real player/payment data out of Staging.
- Do not enable real purchases, creator payouts, or withdrawals in Staging.
- Review every database migration before applying it. The files in `supabase/migrations/` are exported from the already-applied Staging migration history; do not blindly re-run them against this project.

## What's included

- `index.html`: Staging game app with room-scoped game actions and Report Player.
- `scripts/staging-static-check.py`: checks the Staging project reference, required RPC wiring, and inline JavaScript syntax.
- `.github/workflows/staging-static-check.yml`: runs the static checks for changes to the Staging app.
- `supabase/migrations/`: SQL source exports for the migrations recorded in the Staging database.

## Gameplay currently prepared

The Starter question bank contains 100 active questions across Friendship Court, Would You Rather, Truth or Dare, Mind Battle, and Secret Confessions. Friendship Court scoring and final results are implemented. The other four modes currently run as casual response games and do not award points.

## Manual release gate

Before sharing a public Staging URL, confirm GitHub Pages is enabled for this repository and verify the published URL. Browser-level testing with two separate signed-in test accounts is still required. Do not use real player accounts or Production data for this test.
