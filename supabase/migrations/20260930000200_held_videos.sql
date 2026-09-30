-- Low-confidence Shorts are uploaded privately and held until the owner approves them from the app.
alter table public.videos
  add column held boolean not null default false,
  add column confidence smallint check (confidence between 0 and 100);

alter table public.commands drop constraint commands_type_check;
alter table public.commands add constraint commands_type_check check (type in (
  'add_topic', 'reorder_topics', 'skip_topic', 'restore_topic', 'reset_stuck',
  'research', 'make', 'approve_upload', 'publish_now', 'rebuild', 'reschedule',
  'refresh_stats', 'pause', 'resume', 'update_config', 'cleanup', 'approve_video'));
