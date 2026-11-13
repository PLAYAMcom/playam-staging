-- Already applied to Staging as add_flow_trusted_media_processing_queue.
create table if not exists public.flow_media_processing_jobs (
 id uuid primary key default gen_random_uuid(),
 asset_id uuid not null references public.flow_post_assets(id) on delete cascade,
 post_id uuid not null references public.flow_posts(id) on delete cascade,
 creator_auth_user_id uuid not null references auth.users(id) on delete cascade,
 job_type text not null default 'video_ingest' check (job_type in ('video_ingest')),
 status text not null default 'queued' check (status in ('queued','claimed','scanning','transcoding','thumbnailing','completed','failed','rejected')),
 attempts integer not null default 0 check (attempts between 0 and 10),
 max_attempts integer not null default 5 check (max_attempts between 1 and 10),
 available_at timestamptz not null default now(),
 locked_at timestamptz,
 locked_by text,
 last_error_code text,
 last_error_safe_message text,
 output_bucket text,
 output_object_key text,
 thumbnail_object_key text,
 source_sha256 text,
 output_sha256 text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 completed_at timestamptz,
 unique(asset_id,job_type)
);
create index if not exists flow_media_jobs_queue_idx on public.flow_media_processing_jobs(status,available_at,created_at) where status in ('queued','failed');
create index if not exists flow_media_jobs_creator_idx on public.flow_media_processing_jobs(creator_auth_user_id,created_at desc);
alter table public.flow_media_processing_jobs enable row level security;
revoke all on public.flow_media_processing_jobs from public,anon,authenticated;
grant all on public.flow_media_processing_jobs to service_role;

create or replace function public.flow_enqueue_media_processing_v1(p_asset_id uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_asset public.flow_post_assets%rowtype; v_job_id uuid;
begin
 if coalesce(auth.role(),'') <> 'service_role' then raise exception 'service role required' using errcode='42501'; end if;
 select * into v_asset from public.flow_post_assets where id=p_asset_id for update;
 if not found then raise exception 'asset not found' using errcode='P0002'; end if;
 if v_asset.processing_status not in ('quarantined','failed') then raise exception 'asset is not eligible for processing' using errcode='55000'; end if;
 insert into public.flow_media_processing_jobs(asset_id,post_id,creator_auth_user_id)
 values(v_asset.id,v_asset.post_id,v_asset.creator_auth_user_id)
 on conflict(asset_id,job_type) do update
 set status='queued',available_at=now(),updated_at=now(),last_error_code=null,last_error_safe_message=null
 where public.flow_media_processing_jobs.status in ('failed','queued')
 returning id into v_job_id;
 if v_job_id is null then select id into v_job_id from public.flow_media_processing_jobs where asset_id=p_asset_id and job_type='video_ingest'; end if;
 return v_job_id;
end; $$;
revoke all on function public.flow_enqueue_media_processing_v1(uuid) from public,anon,authenticated;
grant execute on function public.flow_enqueue_media_processing_v1(uuid) to service_role;
