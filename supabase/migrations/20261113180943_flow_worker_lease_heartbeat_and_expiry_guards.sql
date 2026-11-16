-- Staging migration: renewable worker leases and terminal-operation expiry guards.
-- The 20-minute lease duration matches the existing claim/recovery RPC.
create or replace function public.flow_renew_media_job_lease_v1(p_job_id uuid, p_worker_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job public.flow_media_processing_jobs%rowtype;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'service role required' using errcode = '42501';
  end if;
  if p_worker_id is null or length(p_worker_id) < 8 or length(p_worker_id) > 120 then
    raise exception 'invalid worker id' using errcode = '22023';
  end if;

  select * into v_job
  from public.flow_media_processing_jobs
  where id = p_job_id
  for update;

  if not found then
    raise exception 'job not found' using errcode = 'P0002';
  end if;
  if v_job.status not in ('scanning', 'transcoding', 'thumbnailing')
     or v_job.locked_by is distinct from p_worker_id
     or v_job.locked_at is null
     or v_job.locked_at < clock_timestamp() - interval '20 minutes' then
    raise exception 'job lease invalid or expired' using errcode = '40001';
  end if;

  update public.flow_media_processing_jobs
  set locked_at = clock_timestamp(), updated_at = clock_timestamp()
  where id = p_job_id
  returning * into v_job;

  return jsonb_build_object('ok', true, 'locked_at', v_job.locked_at);
end;
$$;

revoke all on function public.flow_renew_media_job_lease_v1(uuid, text) from public, anon, authenticated;
grant execute on function public.flow_renew_media_job_lease_v1(uuid, text) to service_role;

create or replace function public.flow_complete_media_job_v1(
  p_job_id uuid, p_worker_id text, p_output_bucket text,
  p_output_object_key text, p_thumbnail_object_key text,
  p_source_sha256 text, p_output_sha256 text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job public.flow_media_processing_jobs%rowtype;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'service role required' using errcode = '42501';
  end if;

  select * into v_job
  from public.flow_media_processing_jobs
  where id = p_job_id
  for update;

  if not found then
    raise exception 'job not found' using errcode = 'P0002';
  end if;
  if v_job.status not in ('scanning', 'transcoding', 'thumbnailing')
     or v_job.locked_by is distinct from p_worker_id
     or v_job.locked_at is null
     or v_job.locked_at < clock_timestamp() - interval '20 minutes' then
    raise exception 'job lease invalid or expired' using errcode = '40001';
  end if;
  if p_output_bucket <> 'flow-media-staging'
     or p_output_object_key not like 'processed/%'
     or p_thumbnail_object_key not like 'processed/%' then
    raise exception 'invalid output location' using errcode = '22023';
  end if;

  update public.flow_post_assets
  set processing_status = 'ready',
      playback_bucket = p_output_bucket,
      playback_object_key = p_output_object_key,
      thumbnail_object_key = p_thumbnail_object_key,
      source_sha256 = p_source_sha256,
      output_sha256 = p_output_sha256
  where id = v_job.asset_id;

  update public.flow_media_processing_jobs
  set status = 'completed',
      output_bucket = p_output_bucket,
      output_object_key = p_output_object_key,
      thumbnail_object_key = p_thumbnail_object_key,
      source_sha256 = p_source_sha256,
      output_sha256 = p_output_sha256,
      completed_at = clock_timestamp(),
      updated_at = clock_timestamp(),
      locked_at = null,
      locked_by = null,
      last_error_code = null,
      last_error_safe_message = null
  where id = p_job_id;

  return jsonb_build_object('ok', true, 'status', 'completed', 'asset_id', v_job.asset_id);
end;
$$;

revoke all on function public.flow_complete_media_job_v1(uuid, text, text, text, text, text, text) from public, anon, authenticated;
grant execute on function public.flow_complete_media_job_v1(uuid, text, text, text, text, text, text) to service_role;

create or replace function public.flow_fail_media_job_v1(
  p_job_id uuid, p_worker_id text, p_error_code text,
  p_safe_message text, p_rejected boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job public.flow_media_processing_jobs%rowtype;
  v_status text;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'service role required' using errcode = '42501';
  end if;

  select * into v_job
  from public.flow_media_processing_jobs
  where id = p_job_id
  for update;

  if not found then
    raise exception 'job not found' using errcode = 'P0002';
  end if;
  if v_job.locked_by is distinct from p_worker_id
     or v_job.status not in ('scanning', 'transcoding', 'thumbnailing')
     or v_job.locked_at is null
     or v_job.locked_at < clock_timestamp() - interval '20 minutes' then
    raise exception 'job lease invalid or expired' using errcode = '40001';
  end if;

  v_status := case when p_rejected then 'rejected' else 'failed' end;

  update public.flow_media_processing_jobs
  set status = v_status,
      available_at = case
        when p_rejected or v_job.attempts >= v_job.max_attempts
          then clock_timestamp() + interval '365 days'
        else clock_timestamp() + make_interval(secs => least(3600, power(2, v_job.attempts)::int * 30))
      end,
      locked_at = null,
      locked_by = null,
      last_error_code = left(coalesce(p_error_code, 'processing_error'), 80),
      last_error_safe_message = left(coalesce(p_safe_message, 'Media processing failed'), 300),
      updated_at = clock_timestamp()
  where id = p_job_id;

  update public.flow_post_assets
  set processing_status = case when p_rejected then 'rejected' else 'failed' end
  where id = v_job.asset_id;

  if p_rejected then
    update public.flow_posts
    set status = 'rejected', moderation_status = 'rejected', updated_at = clock_timestamp()
    where id = v_job.post_id;
  end if;

  return jsonb_build_object('ok', true, 'status', v_status, 'rejected', p_rejected);
end;
$$;

revoke all on function public.flow_fail_media_job_v1(uuid, text, text, text, boolean) from public, anon, authenticated;
grant execute on function public.flow_fail_media_job_v1(uuid, text, text, text, boolean) to service_role;
