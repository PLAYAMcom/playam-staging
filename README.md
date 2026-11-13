# PLAYAM Staging

This repository is the isolated PLAYAM Staging environment. It is not the Production site.

## Safety boundaries

- Staging Supabase project: `pwnjrdedeoxbmtfywhkk`.
- Production Supabase project: `erjxmesxmmmaxivvmbsi`. That reference must never appear in Staging browser files.
- Only the Supabase publishable key belongs in browser code. Never commit service-role keys, secret API keys, passwords, or webhook secrets.
- Keep real player/payment data out of Staging.
- Do not enable real purchases, creator payouts, or withdrawals in Staging.
- Review every database migration before applying it. The files in `supabase/migrations/` are exported from the already-applied Staging migration history; do not blindly re-run them against this project.

## Published site structure

- `site/index.html`: Staging landing page with links to the game and admin dashboard.
- `site/game.html`: published browser game app.
- `site/admin-playam-staging.html`: existing private admin dashboard with authenticator MFA and player-report moderation.
- `index.html`: canonical source for the game page. The static checker verifies that the published copy matches it.

## Checks and deployment

- `scripts/staging-static-check.py` checks project isolation, required RPC wiring, the MFA/report admin page, published-copy consistency, and inline JavaScript syntax.
- `.github/workflows/staging-static-check.yml` runs static checks on relevant changes.
- `.github/workflows/deploy-pages.yml` runs those checks before publishing the `site/` directory to GitHub Pages.
- GitHub Pages must be enabled for this repository with the source set to **GitHub Actions** before the site can publish.

## Gameplay currently prepared

The Starter question bank contains 100 active questions across Friendship Court, Would You Rather, Truth or Dare, Mind Battle, and Secret Confessions. Friendship Court scoring and final results are implemented. The other four modes currently run as casual response games and do not award points.

## Manual release gate

Before sharing a public Staging URL, confirm the Pages deployment succeeded. Browser-level testing with two separate signed-in test accounts is still required. Do not use real player accounts or Production data for this test.
