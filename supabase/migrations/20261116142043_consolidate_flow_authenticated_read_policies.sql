-- Consolidate overlapping authenticated Flow SELECT policies without changing visibility.
-- Anonymous users retain access only to the approved public feed.

drop policy if exists flow_posts_creator_read_own on public.flow_posts;
drop policy if exists flow_posts_public_feed_read on public.flow_posts;
create policy flow_posts_authenticated_read
  on public.flow_posts for select to authenticated
  using (
    (select auth.uid()) = creator_auth_user_id
    or (
      visibility = 'public'
      and status = 'published'
      and moderation_status = 'approved'
    )
  );
create policy flow_posts_public_feed_read
  on public.flow_posts for select to anon
  using (
    visibility = 'public'
    and status = 'published'
    and moderation_status = 'approved'
  );

drop policy if exists flow_assets_creator_read_own on public.flow_post_assets;
drop policy if exists flow_assets_public_feed_read on public.flow_post_assets;
create policy flow_assets_authenticated_read
  on public.flow_post_assets for select to authenticated
  using (
    (select auth.uid()) = creator_auth_user_id
    or (
      processing_status = 'ready'
      and exists (
        select 1 from public.flow_posts p
        where p.id = flow_post_assets.post_id
          and p.visibility = 'public'
          and p.status = 'published'
          and p.moderation_status = 'approved'
      )
    )
  );
create policy flow_assets_public_feed_read
  on public.flow_post_assets for select to anon
  using (
    processing_status = 'ready'
    and exists (
      select 1 from public.flow_posts p
      where p.id = flow_post_assets.post_id
        and p.visibility = 'public'
        and p.status = 'published'
        and p.moderation_status = 'approved'
    )
  );

drop policy if exists flow_comments_author_read_own on public.flow_post_comments;
drop policy if exists flow_comments_public_visible_read on public.flow_post_comments;
create policy flow_comments_authenticated_read
  on public.flow_post_comments for select to authenticated
  using (
    (select auth.uid()) = author_auth_user_id
    or (
      moderation_status = 'visible'
      and exists (
        select 1 from public.flow_posts p
        where p.id = flow_post_comments.post_id
          and p.visibility = 'public'
          and p.status = 'published'
          and p.moderation_status = 'approved'
      )
    )
  );
create policy flow_comments_public_visible_read
  on public.flow_post_comments for select to anon
  using (
    moderation_status = 'visible'
    and exists (
      select 1 from public.flow_posts p
      where p.id = flow_post_comments.post_id
        and p.visibility = 'public'
        and p.status = 'published'
        and p.moderation_status = 'approved'
    )
  );