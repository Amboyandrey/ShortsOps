-- Queue edits (add, skip, restore, reorder topics) may wait up to 7 days for an offline laptop;
-- everything else, including anything that builds or publishes, keeps the 24-hour ceiling.

create or replace function private.max_command_ttl(command_type text) returns interval
language sql immutable
as $$
  select case when command_type in ('add_topic', 'skip_topic', 'restore_topic', 'reorder_topics')
              then interval '7 days' else interval '24 hours' end
$$;

grant execute on function private.max_command_ttl(text) to authenticated;

drop policy owner_insert on public.commands;
create policy owner_insert on public.commands for insert to authenticated
  with check (private.app_role() = 'owner' and created_by = auth.uid() and status = 'pending'
              and expires_at <= now() + private.max_command_ttl(type));
