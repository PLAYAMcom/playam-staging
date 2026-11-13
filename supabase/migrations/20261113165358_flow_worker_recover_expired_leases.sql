-- Already applied to Staging as flow_worker_recover_expired_leases.
-- Recover workers that disappeared mid-job, while enforcing the retry ceiling.
create or replace function public.flow_claim_media_job_v1(p_worker_id text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_job public.flow_media_processing_jobs%rowtype; v_asset public.flow_post_assets%rowtype;
begin
 if coalesce(auth.role(),'') <> 'service_role' then raise exception 'service role required' using errcode='42501'; end if;
 if p_worker_id is null or length(p_worker_id)<8 or length(p_worker_id)>120 then raise exception 'invalid worker id' using errcode='22023'; end if;
 update public.flow_media_processing_jobs
 set status='failed',locked_at=null,locked_by=null,last_error_code='worker_lease_expired',last_error_safe_message='Worker stopped before completing media processing.',updated_at=now()
 where status in ('scanning','transcoding','thumbnailing') and locked_at < now()-interval '30 minutes' and attempts>=max_attempts;
 select * into v_job from public.flow_media_processing_jobs
 where ((status in ('queued','failed') and available_at<=now()) or
        (status in ('scanning','transcoding','thumbnailing') and locked_at < now()-interval '30 minutes'))
   and attempts<max_attempts
 order by available_at,created_at for update skip locked limit 1;
 if not found then return null; end if;
 update public.flow_media_processing_jobs set status='scanning',attempts=attempts+1,locked_at=now(),locked_by=p_worker_id,updated_at=now()
 where id=v_job.id returning * into v_job;
 update public.flow_post_assets set processing_status='scanning' where id=v_job.asset_id returning * into v_asset;
 return jsonb_build_object('job_id',v_job.id,'asset_id',v_asset.id,'post_id',v_asset.post_id,'creator_auth_user_id',v_asset.creator_auth_user_id,'source_bucket',v_asset.storage_bucket,'source_object_key',v_asset.storage_object_key,'declared_mime_type',v_asset.mime_type,'attempt',v_job.attempts,'worker_id',p_worker_id);
end; $$;
revoke all on function public.flow_claim_media_job_v1(text) from public,anon,authenticated;
grant execute on function public.flow_claim_media_job_v1(text) to service_role;
