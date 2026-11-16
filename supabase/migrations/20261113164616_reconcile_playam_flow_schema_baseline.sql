-- Already applied to Staging as reconcile_playam_flow_schema_baseline.
create table if not exists public.flow_posts (
 id uuid primary key default gen_random_uuid(),
 creator_auth_user_id uuid not null references auth.users(id) on delete cascade,
 caption text not null default '' check (char_length(caption) <= 2200),
 visibility text not null default 'public' check (visibility in ('public','followers','private')),
 status text not null default 'draft' check (status in ('draft','pending_review','processing','published','rejected','removed')),
 moderation_status text not null default 'pending' check (moderation_status in ('pending','approved','rejected','limited','removed')),
 published_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.flow_post_assets (
 id uuid primary key default gen_random_uuid(),
 post_id uuid not null references public.flow_posts(id) on delete cascade,
 creator_auth_user_id uuid not null references auth.users(id) on delete cascade,
 storage_bucket text not null, storage_object_key text not null,
 media_type text not null check (media_type in ('video','image')),
 mime_type text not null, duration_seconds numeric(8,2) check (duration_seconds is null or duration_seconds >= 0),
 width integer check (width is null or width > 0), height integer check (height is null or height > 0),
 processing_status text not null default 'quarantined' check (processing_status in ('quarantined','scanning','processing','ready','rejected','failed')),
 thumbnail_object_key text, created_at timestamptz not null default now(), unique(storage_bucket,storage_object_key)
);
create table if not exists public.flow_post_likes (
 post_id uuid not null references public.flow_posts(id) on delete cascade,
 user_auth_user_id uuid not null references auth.users(id) on delete cascade,
 created_at timestamptz not null default now(), primary key(post_id,user_auth_user_id)
);
create table if not exists public.flow_post_comments (
 id uuid primary key default gen_random_uuid(), post_id uuid not null references public.flow_posts(id) on delete cascade,
 author_auth_user_id uuid not null references auth.users(id) on delete cascade,
 parent_comment_id uuid references public.flow_post_comments(id) on delete cascade,
 body text not null check (char_length(btrim(body)) between 1 and 2000),
 moderation_status text not null default 'visible' check (moderation_status in ('visible','pending','hidden','removed')),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.flow_follows (
 follower_auth_user_id uuid not null references auth.users(id) on delete cascade,
 followed_auth_user_id uuid not null references auth.users(id) on delete cascade,
 created_at timestamptz not null default now(), primary key(follower_auth_user_id,followed_auth_user_id),
 check (follower_auth_user_id <> followed_auth_user_id)
);
create table if not exists public.flow_view_events (
 id uuid primary key default gen_random_uuid(), post_id uuid not null references public.flow_posts(id) on delete cascade,
 viewer_auth_user_id uuid references auth.users(id) on delete set null,
 event_dedupe_key text not null unique, qualified boolean not null default false,
 watch_time_ms integer not null default 0 check (watch_time_ms >= 0),
 validation_source text not null default 'server' check (validation_source in ('server','moderation_review')),
 created_at timestamptz not null default now()
);
create table if not exists public.flow_creator_metrics_daily (
 creator_auth_user_id uuid not null references auth.users(id) on delete cascade, metric_date date not null,
 follower_count bigint not null default 0 check (follower_count >= 0),
 qualified_views bigint not null default 0 check (qualified_views >= 0),
 watch_time_ms bigint not null default 0 check (watch_time_ms >= 0),
 likes bigint not null default 0 check (likes >= 0), comments bigint not null default 0 check (comments >= 0),
 shares bigint not null default 0 check (shares >= 0), updated_at timestamptz not null default now(),
 primary key(creator_auth_user_id,metric_date)
);
create table if not exists public.flow_creator_eligibility (
 creator_auth_user_id uuid primary key references auth.users(id) on delete cascade,
 eligibility_status text not null default 'locked' check (eligibility_status in ('locked','in_review','eligible','suspended','rejected')),
 policy_version text, minimum_followers bigint check (minimum_followers is null or minimum_followers >= 0),
 minimum_qualified_views bigint check (minimum_qualified_views is null or minimum_qualified_views >= 0),
 measurement_window_days integer check (measurement_window_days is null or measurement_window_days > 0),
 evaluated_followers bigint not null default 0 check (evaluated_followers >= 0),
 evaluated_qualified_views bigint not null default 0 check (evaluated_qualified_views >= 0),
 account_in_good_standing boolean not null default false, original_content_verified boolean not null default false,
 last_evaluated_at timestamptz, reviewed_by uuid references auth.users(id) on delete set null,
 reviewed_at timestamptz, review_reason text, updated_at timestamptz not null default now()
);
create table if not exists public.flow_content_moderation (
 id uuid primary key default gen_random_uuid(), post_id uuid not null references public.flow_posts(id) on delete cascade,
 reporter_auth_user_id uuid references auth.users(id) on delete set null,
 reason_code text not null, details text,
 review_status text not null default 'open' check (review_status in ('open','reviewing','actioned','dismissed','appealed')),
 reviewer_auth_user_id uuid references auth.users(id) on delete set null,
 decision_reason text, created_at timestamptz not null default now(), reviewed_at timestamptz
);
create index if not exists flow_posts_creator_created_idx on public.flow_posts(creator_auth_user_id,created_at desc);
create index if not exists flow_posts_feed_idx on public.flow_posts(status,moderation_status,visibility,published_at desc);
create index if not exists flow_assets_post_idx on public.flow_post_assets(post_id);
create index if not exists flow_comments_post_created_idx on public.flow_post_comments(post_id,created_at desc);
create index if not exists flow_follows_followed_idx on public.flow_follows(followed_auth_user_id,created_at desc);
create index if not exists flow_views_post_created_idx on public.flow_view_events(post_id,created_at desc);
create index if not exists flow_views_creator_validation_idx on public.flow_view_events(qualified,created_at desc);
create index if not exists flow_moderation_status_created_idx on public.flow_content_moderation(review_status,created_at);
alter table public.flow_posts enable row level security;
alter table public.flow_post_assets enable row level security;
alter table public.flow_post_likes enable row level security;
alter table public.flow_post_comments enable row level security;
alter table public.flow_follows enable row level security;
alter table public.flow_view_events enable row level security;
alter table public.flow_creator_metrics_daily enable row level security;
alter table public.flow_creator_eligibility enable row level security;
alter table public.flow_content_moderation enable row level security;
revoke all on public.flow_posts,public.flow_post_assets,public.flow_post_likes,public.flow_post_comments,public.flow_follows,public.flow_view_events,public.flow_creator_metrics_daily,public.flow_creator_eligibility,public.flow_content_moderation from public,anon,authenticated;
grant all on public.flow_posts,public.flow_post_assets,public.flow_post_likes,public.flow_post_comments,public.flow_follows,public.flow_view_events,public.flow_creator_metrics_daily,public.flow_creator_eligibility,public.flow_content_moderation to service_role;
