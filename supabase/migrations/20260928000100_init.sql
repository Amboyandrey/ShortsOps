-- ShortsOps core schema: a mirror of the laptop pipeline's state plus a command queue.
-- Two roles, both carried in app_metadata (not user-editable): 'owner' (the app) and 'agent' (the laptop).

create schema if not exists private;

-- Role of the calling user, or '' for anyone else.
create or replace function private.app_role() returns text
language sql stable
as $$ select coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') $$;

grant usage on schema private to authenticated;
grant execute on function private.app_role() to authenticated;

-- ------------------------------------------------------------------ mirrored state (agent writes, owner reads)

create table public.topics (
  id                text primary key,
  topic             text not null,
  status            text not null default 'pending'
                    check (status in ('pending', 'building', 'built', 'uploaded', 'failed', 'skipped')),
  position          integer not null default 0,
  subniche          text,
  hook              text,
  why_it_works      text,
  fact_check_notes  text,
  inspired_by       text,
  video_id          text,
  out_dir           text,
  created_at        timestamptz,
  synced_at         timestamptz not null default now()
);
create index topics_status_position_idx on public.topics (status, position);

create table public.builds (
  id              text primary key,             -- data/out/<dir> name
  topic_id        text,
  title           text not null,
  description     text,
  tags            text[] not null default '{}',
  confidence      integer check (confidence between 0 and 100),
  fact_check      text,
  duration_s      real,
  mood            text,
  video_id        text,
  size_bytes      bigint,
  preview_path    text,                          -- object in the private 'previews' bucket
  created_at      timestamptz,
  synced_at       timestamptz not null default now()
);
create index builds_topic_idx on public.builds (topic_id);
create index builds_created_idx on public.builds (created_at desc);

create table public.videos (
  video_id          text primary key,
  topic_id          text,
  build_id          text,
  topic             text,
  title             text not null,
  publish_at        timestamptz,
  privacy           text,
  views             bigint,
  likes             bigint,
  comments          bigint,
  stats_updated_at  timestamptz,
  created_at        timestamptz,
  synced_at         timestamptz not null default now()
);
create index videos_publish_idx on public.videos (publish_at desc);

create table public.competitors (
  ref           text primary key,
  name          text not null,
  top10_mean    bigint,
  median_views  bigint,
  max_views     bigint,
  top           jsonb not null default '[]',
  synced_at     timestamptz not null default now()
);

-- Single-row tables: the id check keeps them single.
create table public.agent_status (
  id                smallint primary key default 1 check (id = 1),
  last_seen         timestamptz not null default now(),
  version           text,
  paused            boolean not null default false,
  cron_installed    boolean,
  last_run_date     date,
  running_command   uuid,
  quota_units_used  integer,
  uploads_left      integer,
  disk_free_bytes   bigint,
  out_dir_bytes     bigint
);

create table public.config_snapshot (
  id          smallint primary key default 1 check (id = 1),
  config      jsonb not null,
  synced_at   timestamptz not null default now()
);

create table public.runs (
  id           uuid primary key default gen_random_uuid(),
  kind         text not null,
  status       text not null default 'running' check (status in ('running', 'succeeded', 'failed')),
  step         text,
  command_id   uuid,
  error        text,
  started_at   timestamptz not null default now(),
  finished_at  timestamptz
);
create index runs_started_idx on public.runs (started_at desc);

create table public.events (
  id          bigint generated always as identity primary key,
  kind        text not null check (kind in ('short_built', 'low_confidence', 'run_failed', 'went_live',
                                             'quota_blocked', 'agent_online', 'command_failed')),
  title       text not null,
  body        text,
  ref         jsonb not null default '{}',
  created_at  timestamptz not null default now()
);
create index events_created_idx on public.events (created_at desc);

-- ------------------------------------------------------------------ command queue (owner writes, agent executes)

create table public.commands (
  id           uuid primary key default gen_random_uuid(),
  type         text not null check (type in (
                 'add_topic', 'reorder_topics', 'skip_topic', 'restore_topic', 'reset_stuck',
                 'research', 'make', 'approve_upload', 'publish_now', 'rebuild', 'reschedule',
                 'refresh_stats', 'pause', 'resume', 'update_config', 'cleanup')),
  payload      jsonb not null default '{}' check (jsonb_typeof(payload) = 'object' and pg_column_size(payload) < 4096),
  status       text not null default 'pending'
               check (status in ('pending', 'claimed', 'done', 'failed', 'expired', 'cancelled')),
  created_by   uuid not null default auth.uid() references auth.users (id) on delete cascade,
  created_at   timestamptz not null default now(),
  expires_at   timestamptz not null default now() + interval '1 hour',
  claimed_at   timestamptz,
  finished_at  timestamptz,
  result       jsonb,
  error        text
);
create index commands_pending_idx on public.commands (created_at) where status = 'pending';

create table public.devices (
  token       text primary key,
  user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  platform    text not null check (platform in ('android', 'ios')),
  created_at  timestamptz not null default now(),
  last_seen   timestamptz not null default now()
);

-- ------------------------------------------------------------------ privileges: nothing for anon, explicit for authenticated

alter table public.topics          enable row level security;
alter table public.builds          enable row level security;
alter table public.videos          enable row level security;
alter table public.competitors     enable row level security;
alter table public.agent_status    enable row level security;
alter table public.config_snapshot enable row level security;
alter table public.runs            enable row level security;
alter table public.events          enable row level security;
alter table public.commands        enable row level security;
alter table public.devices         enable row level security;

revoke all on all tables in schema public from anon, authenticated;

grant select, insert, update, delete on public.topics, public.builds, public.videos, public.competitors,
  public.agent_status, public.config_snapshot to authenticated;
grant select, insert, update on public.runs to authenticated;
grant select, insert on public.events to authenticated;
grant select, insert, update on public.commands to authenticated;
grant select, insert, update, delete on public.devices to authenticated;

-- Mirrored tables: owner reads, agent does everything.
do $$
declare t text;
begin
  foreach t in array array['topics', 'builds', 'videos', 'competitors', 'agent_status', 'config_snapshot', 'runs', 'events']
  loop
    execute format('create policy owner_read on public.%I for select to authenticated using (private.app_role() = ''owner'')', t);
    execute format('create policy agent_all on public.%I for all to authenticated using (private.app_role() = ''agent'') with check (private.app_role() = ''agent'')', t);
  end loop;
end $$;

-- Commands: the owner creates and may cancel pending ones; the agent reads and finishes them.
create policy owner_read on public.commands for select to authenticated
  using (private.app_role() = 'owner' and created_by = auth.uid());
create policy owner_insert on public.commands for insert to authenticated
  with check (private.app_role() = 'owner' and created_by = auth.uid() and status = 'pending'
              and expires_at <= now() + interval '24 hours');
create policy owner_cancel on public.commands for update to authenticated
  using (private.app_role() = 'owner' and created_by = auth.uid() and status = 'pending')
  with check (status = 'cancelled');
create policy agent_read on public.commands for select to authenticated
  using (private.app_role() = 'agent');
create policy agent_update on public.commands for update to authenticated
  using (private.app_role() = 'agent') with check (private.app_role() = 'agent');

-- Devices: the owner manages their own push tokens; the agent never sees them.
create policy owner_devices on public.devices for all to authenticated
  using (private.app_role() = 'owner' and user_id = auth.uid())
  with check (private.app_role() = 'owner' and user_id = auth.uid());

-- ------------------------------------------------------------------ command claiming

-- Atomically hands the agent the oldest live command, expiring stale ones first.
create or replace function public.claim_command() returns setof public.commands
language plpgsql
set search_path = ''
as $$
begin
  if private.app_role() <> 'agent' then
    raise exception 'only the agent may claim commands' using errcode = '42501';
  end if;

  update public.commands set status = 'expired', finished_at = now()
   where status = 'pending' and expires_at <= now();

  return query
  update public.commands c
     set status = 'claimed', claimed_at = now()
   where c.id = (select id from public.commands
                  where status = 'pending'
                  order by created_at
                  for update skip locked
                  limit 1)
  returning c.*;
end $$;

revoke execute on function public.claim_command() from public, anon;
grant execute on function public.claim_command() to authenticated;

-- ------------------------------------------------------------------ realtime

alter publication supabase_realtime add table
  public.commands, public.agent_status, public.runs, public.events, public.topics, public.builds, public.videos;

-- ------------------------------------------------------------------ storage: preview clips, private

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('previews', 'previews', false, 15728640, array['video/mp4', 'image/jpeg']);

create policy previews_owner_read on storage.objects for select to authenticated
  using (bucket_id = 'previews' and private.app_role() = 'owner');
create policy previews_agent_all on storage.objects for all to authenticated
  using (bucket_id = 'previews' and private.app_role() = 'agent')
  with check (bucket_id = 'previews' and private.app_role() = 'agent');
