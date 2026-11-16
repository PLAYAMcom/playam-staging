-- Already applied to Staging as secure_flow_upload_intents_and_quotas.
create table if not exists public.flow_upload_intents (
 id uuid primary key default gen_random_uuid(),
 creator_auth_user_id uuid not null references auth.users(id) on delete cascade,
 storage_bucket text not null default 'flow-media-staging' check (storage_bucket='flow-media-staging'),
 storage_object_key text not null unique,
 declared_mime_type text not null check (declared_mime_type in ('video/mp4','video/quicktime','video/webm')),
 status text not null default 'issued' check (status in ('issued','consumed','expired','rejected')),
 expires_at timestamptz not null,
 consumed_at timestamptz,
 created_at timestamptz not null default now()
);
create index if not exists flow_upload_intents_user_created_idx on public.flow_upload_intents(creator_auth_user_id,created_at desc);
alter table public.flow_upload_intents enable row level security;
revoke all on public.flow_upload_intents from public,anon,authenticated;
grant all on public.flow_upload_intents to service_role;
