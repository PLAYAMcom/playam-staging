# Staging migration history reconciliation

This file is documentation only. It is **not** a SQL migration and must not be executed.

## Verified current state

- Staging project: `pwnjrdedeoxbmtfywhkk`
- Staging migration history contains 63 entries.
- Every SQL migration file currently tracked under `supabase/migrations/` on the Staging PR branch has a matching version in the Staging migration history.
- No repository migration file is currently pending in Staging.
- The private-message baseline and related report/read-receipt migrations were reapplied idempotently after checking their live schema effects. Their repository filenames now match the actual Staging migration versions.
- The combined market-foundation reference SQL was removed from the migration queue because the same schema is already represented by separate applied market migrations.

## Historical source files missing from this repository

The following migrations are recorded as applied in Staging but their original SQL files are not present in the repository tree. They were not recreated as empty placeholders because doing so would falsely imply that the original SQL is recoverable.

| Applied version | Recorded migration name |
|---|---|
| 20261113160631 | secure_flow_media_staging_storage_access |
| 20261113164616 | reconcile_playam_flow_schema_baseline |
| 20261113164758 | secure_flow_admin_review_atomic |
| 20261113164906 | secure_flow_upload_intents_and_quotas |
| 20261113165033 | add_flow_trusted_media_processing_queue |
| 20261113165153 | add_flow_atomic_media_job_claim |
| 20261113165218 | deploy_flow_worker_claim_complete_and_fail_rpc |
| 20261113165358 | flow_worker_recover_expired_leases |
| 20261113165700 | recover_stale_flow_media_worker_jobs |
| 20261113180943 | flow_worker_lease_heartbeat_and_expiry_guards |
| 20261113231823 | harden_financial_ledger_privileges |
| 20261113231939 | restrict_payment_and_coin_wallet_mutations |
| 20261113232024 | tighten_social_privacy_and_message_policies |
| 20261113232411 | add_verified_paystack_coin_credit_rpc |
| 20261115164039 | add_cloudflare_stream_staging_uploads |
| 20261115164111 | add_cloudflare_thumbnail_metadata |
| 20261115164143 | store_cloudflare_playback_metadata |
| 20261115211251 | secure_playam_video_rls_access |
| 20261115214830 | lock_live_gift_event_ledger_mutations |
| 20261115220612 | add_global_market_configuration_foundation |
| 20261115220711 | add_service_role_policies_to_private_market_config |
| 20261115220740 | add_user_market_preferences_with_rls |
| 20261115220750 | secure_user_market_preference_rpc |
| 20261115220945 | add_available_market_listing_rpc |
| 20261115222001 | add_multi_currency_creator_ledger_v1 |
| 20261115222053 | make_creator_currency_ledger_append_only_v1 |
| 20261116044230 | harden_creator_payout_backend_calls_v1 |
| 20261116044522 | prepare_idempotent_paystack_creator_transfers_v1 |
| 20261116044726 | claim_paystack_payout_attempt_once_v1 |
| 20261116044731 | fix_atomic_transfer_claim_result_v1 |
| 20261116044751 | restrict_payout_attempt_table_permissions_v1 |
| 20261116044901 | prevent_duplicate_creator_payout_submission |
| 20261116053124 | private_messaging_read_receipts_and_realtime |

## Required before rebuilding another environment

Recover the original SQL for these historical versions from the original development archive or another trusted source, then commit those exact files. Do not generate no-op files or alter Staging migration history to conceal the gap. Until the source archive is restored, Staging is verified against its live migration ledger, but this repository is not a complete historical migration archive.

Production has not been modified.
