-- Already applied to Staging as deploy_flow_worker_claim_complete_and_fail_rpc.
-- This checked-in migration makes the deployed worker contract reproducible.
alter table public.flow_post_assets
 add column if not exists playback_bucket text,
 add column if not exists playback_object_key text,
 add column if not exists source_sha256 text,
 add column if not exists output_sha256 text;

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

create or replace function public.flow_complete_media_job_v1(p_job_id uuid,p_worker_id text,p_output_bucket text,p_output_object_key text,p_thumbnail_object_key text,p_source_sha256 text,p_output_sha256 text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_job public.flow_media_processing_jobs%rowtype;
begin
 if coalesce(auth.role(),'') <> 'service_role' then raise exception 'service role required' using errcode='42501'; end if;
 select * into v_job from public.flow_media_processing_jobs where id=p_job_id for update;
 if not found then raise exception 'job not found' using errcode='P0002'; end if;
 if v_job.status not in ('scanning','transcoding','thumbnailing') or v_job.locked_by<>p_worker_id then raise exception 'job lease invalid' using errcode='40001'; end if;
 if p_output_bucket<>'flow-media-staging' or p_output_object_key not like 'processed/%' or p_thumbnail_object_key not like 'processed/%' then raise exception 'invalid output location' using errcode='22023'; end if;
 update public.flow_post_assets set processing_status='ready',playback_bucket=p_output_bucket,playback_object_key=p_output_object_key,thumbnail_object_key=p_thumbnail_object_key,source_sha256=p_source_sha256,output_sha256=p_output_sha256 where id=v_job.asset_id;
 update public.flow_media_processing_jobs set status='completed',output_bucket=p_output_bucket,output_object_key=p_output_object_key,thumbnail_object_key=p_thumbnail_object_key,source_sha256=p_source_sha256,output_sha256=p_output_sha256,completed_at=now(),updated_at=now(),locked_at=null,locked_by=null,last_error_code=null,last_error_safe_message=null where id=p_job_id;
 return jsonb_build_object('ok',true,'status','completed','asset_id',v_job.asset_id);
end; $$;
revoke all on function public.flow_complete_media_job_v1(uuid,text,text,text,text,text,text) from public,anon,authenticated;
grant execute on function public.flow_complete_media_job_v1(uuid,text,text,text,text,text,text) to service_role;

create or replace function public.flow_fail_media_job_v1(p_job_id uuid,p_worker_id text,p_error_code text,p_safe_message text,p_rejected boolean default false)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_job public.flow_media_processing_jobs%rowtype; v_status text;
begin
 if coalesce(auth.role(),'') <> 'service_role' then raise exception 'service role required' using errcode='42501'; end if;
 select * into v_job from public.flow_media_processing_jobs where id=p_job_id for update;
 if not found then raise exception 'job not found' using errcode='P0002'; end if;
 if v_job.locked_by<>p_worker_id or v_job.status not in ('scanning','transcoding','thumbnailing') then raise exception 'job lease invalid' using errcode='40001'; end if;
 v_status:=case when p_rejected then 'rejected' else 'failed' end;
 update public.flow_media_processing_jobs set status=v_status,available_at=case when p_rejected or v_job.attempts>=v_job.max_attempts then now()+interval '365 days' else now()+make_interval(secs=>least(3600,power(2,v_job.attempts)::int*30)) end,locked_at=null,locked_by=null,last_error_code=left(coalesce(p_error_code,'processing_error'),80),last_error_safe_message=left(coalesce(p_safe_message,'Media processing failed'),300),updated_at=now() where id=p_job_id;
 update public.flow_post_assets set processing_status=case when p_rejected then 'rejected' else 'failed' end where id=v_job.asset_id;
 if p_rejected then update public.flow_posts set status='rejected',moderation_status='rejected',updated_at=now() where id=v_job.post_id; end if;
 return jsonb_build_object('ok',true,'status',v_status,'rejected',p_rejected);
end; $$;
revoke all on function public.flow_fail_media_job_v1(uuid,text,text,text,boolean) from public,anon,authenticated;
grant execute on function public.flow_fail_media_job_v1(uuid,text,text,text,boolean) to service_role;
