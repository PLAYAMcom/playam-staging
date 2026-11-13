-- Already applied to Staging as secure_flow_admin_review_atomic.
create or replace function public.flow_admin_review_post_v1(
 p_post_id uuid,p_reviewer_auth_user_id uuid,p_decision text,p_reason text default null
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_post public.flow_posts%rowtype; v_asset public.flow_post_assets%rowtype; v_now timestamptz:=now();
begin
 if coalesce(auth.role(),'') <> 'service_role' then raise exception 'service role required' using errcode='42501'; end if;
 if p_decision not in ('approve','reject') then raise exception 'invalid decision' using errcode='22023'; end if;
 select * into v_post from public.flow_posts where id=p_post_id for update;
 if not found then raise exception 'post not found' using errcode='P0002'; end if;
 if v_post.status <> 'draft' or v_post.moderation_status <> 'pending' then raise exception 'post is no longer awaiting review' using errcode='40001'; end if;
 select * into v_asset from public.flow_post_assets where post_id=p_post_id limit 1 for update;
 if not found then raise exception 'video asset missing' using errcode='23503'; end if;
 if p_decision='approve' and v_asset.processing_status <> 'ready' then raise exception 'media has not passed trusted processing' using errcode='55000'; end if;
 update public.flow_posts set moderation_status=case when p_decision='approve' then 'approved' else 'rejected' end,
 status=case when p_decision='approve' then 'published' else 'rejected' end,
 visibility=case when p_decision='approve' then 'public' else visibility end,
 published_at=case when p_decision='approve' then v_now else published_at end,updated_at=v_now where id=p_post_id;
 insert into public.flow_content_moderation(post_id,reporter_auth_user_id,reason_code,details,review_status,reviewer_auth_user_id,decision_reason,reviewed_at)
 values(p_post_id,null,'prepublication_review','Administrator pre-publication review','actioned',p_reviewer_auth_user_id,left(coalesce(p_reason,''),1000),v_now);
 return jsonb_build_object('ok',true,'decision',p_decision,'post_id',p_post_id);
end; $$;
revoke all on function public.flow_admin_review_post_v1(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.flow_admin_review_post_v1(uuid,uuid,text,text) to service_role;
