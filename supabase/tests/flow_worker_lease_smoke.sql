-- PLAYAM Flow worker lease integration smoke test.
-- Run against a disposable Staging database/session with permission to set the
-- request.jwt.claim.role setting. All fixture rows are rolled back at the end.
-- This verifies sequential competing claims and stale-lease guards; it does not
-- replace a true two-connection SKIP LOCKED contention test.
begin;
do $$
declare
  v_user uuid;
  v_post uuid;
  v_asset uuid;
  v_job uuid;
  v_claim jsonb;
  v_claim2 jsonb;
  v_renew jsonb;
  v_rejected boolean;
begin
  perform set_config('request.jwt.claim.role', 'service_role', true);
  select id into v_user from auth.users order by created_at limit 1;
  if v_user is null then
    raise exception 'An auth.users row is required for the temporary FK-backed fixture';
  end if;

  insert into public.flow_posts(creator_auth_user_id, caption, status, moderation_status, visibility)
  values (v_user, 'ROLLBACK ONLY: flow worker lease integration test', 'processing', 'pending', 'private')
  returning id into v_post;

  insert into public.flow_post_assets(
    post_id, creator_auth_user_id, storage_bucket, storage_object_key,
    media_type, mime_type, processing_status
  )
  values (
    v_post, v_user, 'flow-media-staging',
    'lease-test/' || gen_random_uuid() || '/source.mp4',
    'video', 'video/mp4', 'quarantined'
  )
  returning id into v_asset;

  insert into public.flow_media_processing_jobs(
    asset_id, post_id, creator_auth_user_id, status, attempts, max_attempts, available_at
  )
  values (v_asset, v_post, v_user, 'queued', 0, 5, now() - interval '1 second')
  returning id into v_job;

  v_claim := public.flow_claim_media_job_v1('lease-test-worker-0001');
  if v_claim is null or (v_claim->>'job_id')::uuid <> v_job then
    raise exception 'First worker did not claim the isolated fixture: %', v_claim;
  end if;

  v_claim2 := public.flow_claim_media_job_v1('lease-test-worker-0002');
  if v_claim2 is not null then
    raise exception 'Second worker claimed a job already held by first worker: %', v_claim2;
  end if;

  v_renew := public.flow_renew_media_job_lease_v1(v_job, 'lease-test-worker-0001');
  if v_renew->>'ok' <> 'true' then
    raise exception 'Valid lease renewal not confirmed: %', v_renew;
  end if;

  v_rejected := false;
  begin
    perform public.flow_renew_media_job_lease_v1(v_job, 'lease-test-worker-wrong');
  exception when sqlstate '40001' then
    v_rejected := true;
  end;
  if not v_rejected then
    raise exception 'Wrong worker was allowed to renew the lease';
  end if;

  update public.flow_media_processing_jobs
  set locked_at = clock_timestamp() - interval '21 minutes'
  where id = v_job;

  v_rejected := false;
  begin
    perform public.flow_renew_media_job_lease_v1(v_job, 'lease-test-worker-0001');
  exception when sqlstate '40001' then
    v_rejected := true;
  end;
  if not v_rejected then raise exception 'Expired lease renewal was not rejected'; end if;

  v_rejected := false;
  begin
    perform public.flow_complete_media_job_v1(
      v_job, 'lease-test-worker-0001', 'flow-media-staging',
      'processed/test/playback.mp4', 'processed/test/thumbnail.jpg',
      repeat('a', 64), repeat('b', 64)
    );
  exception when sqlstate '40001' then
    v_rejected := true;
  end;
  if not v_rejected then raise exception 'Expired lease completion was not rejected'; end if;

  v_rejected := false;
  begin
    perform public.flow_fail_media_job_v1(
      v_job, 'lease-test-worker-0001', 'test', 'test stale lease', false
    );
  exception when sqlstate '40001' then
    v_rejected := true;
  end;
  if not v_rejected then raise exception 'Expired lease failure transition was not rejected'; end if;

  v_claim := public.flow_claim_media_job_v1('lease-test-worker-0003');
  if v_claim is null
     or (v_claim->>'job_id')::uuid <> v_job
     or v_claim->>'worker_id' <> 'lease-test-worker-0003' then
    raise exception 'Expired job was not safely reclaimed by new worker: %', v_claim;
  end if;
end
$$;
rollback;
