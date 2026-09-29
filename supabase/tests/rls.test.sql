begin;
select plan(24);

-- Three callers: the owner, the agent, and a signed-in user with no role.
insert into auth.users (id, email, raw_app_meta_data) values
  ('00000000-0000-0000-0000-00000000000a', 'owner@test', '{"role": "owner"}'),
  ('00000000-0000-0000-0000-00000000000b', 'agent@test', '{"role": "agent"}'),
  ('00000000-0000-0000-0000-00000000000c', 'nobody@test', '{}');

create function pg_temp.act_as(uid uuid, role text) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', uid, 'role', 'authenticated', 'app_metadata', json_build_object('role', role))::text, true);
$$;

-- ---------------------------------------------------------------- agent writes the mirror
set local role authenticated;
select pg_temp.act_as('00000000-0000-0000-0000-00000000000b', 'agent');

select lives_ok($$ insert into public.topics (id, topic) values ('t1', 'Why cats purr') $$, 'agent inserts topics');
select lives_ok($$ update public.topics set status = 'built' where id = 't1' $$, 'agent updates topics');
select lives_ok($$ insert into public.agent_status (id, paused) values (1, false) $$, 'agent writes agent_status');
select throws_ok($$ insert into public.agent_status (id) values (2) $$, '23514', null, 'agent_status stays single-row');
select throws_ok($$ insert into public.commands (type) values ('research') $$, '42501', null, 'agent cannot create commands');
select is((select count(*) from public.devices), 0::bigint, 'agent sees no device tokens');

-- ---------------------------------------------------------------- owner reads and commands
select pg_temp.act_as('00000000-0000-0000-0000-00000000000a', 'owner');

select is((select status from public.topics where id = 't1'), 'built', 'owner reads topics');
select is_empty($$ update public.topics set status = 'pending' where id = 't1' returning id $$, 'owner cannot modify topics');
select throws_ok($$ insert into public.topics (id, topic) values ('t2', 'x') $$, '42501', null, 'owner cannot insert topics');
select lives_ok($$ insert into public.commands (id, type, payload) values
  ('10000000-0000-0000-0000-000000000001', 'research', '{"n": 5}') $$, 'owner creates a command');
select throws_ok($$ insert into public.commands (type, status) values ('research', 'done') $$, '42501', null,
  'owner cannot create a command in a finished state');
select throws_ok($$ insert into public.commands (type, expires_at) values ('research', now() + interval '3 days') $$, '42501', null,
  'owner cannot create a long-lived command');
select lives_ok($$ insert into public.commands (id, type, payload, expires_at) values
  ('10000000-0000-0000-0000-000000000003', 'add_topic', '{"text": "Why flamingos are pink"}', now() + interval '7 days') $$,
  'queue edits may wait a week for the laptop');
select lives_ok($$ update public.commands set status = 'cancelled' where id = '10000000-0000-0000-0000-000000000003' $$,
  'owner can cancel a waiting command');
select throws_ok($$ insert into public.commands (type, expires_at) values ('make', now() + interval '7 days') $$, '42501', null,
  'a build cannot wait a week');
select throws_ok($$ insert into public.commands (type, payload, expires_at) values
  ('add_topic', '{"text": "x"}', now() + interval '8 days') $$, '42501', null, 'queue edits are capped at 7 days');
select throws_ok($$ insert into public.commands (type) values ('rm_rf') $$, '23514', null, 'unknown command types are rejected');
select throws_ok($$ update public.commands set status = 'done' where id = '10000000-0000-0000-0000-000000000001' $$, '42501', null,
  'owner cannot mark a command done');
select throws_ok($$ select * from public.claim_command() $$, '42501', null, 'owner cannot claim commands');

-- ---------------------------------------------------------------- agent claims exactly once, stale commands expire
insert into public.commands (id, type, expires_at) values
  ('10000000-0000-0000-0000-000000000002', 'make', now() + interval '1 second');
select pg_temp.act_as('00000000-0000-0000-0000-00000000000b', 'agent');
update public.commands set expires_at = now() - interval '1 minute' where id = '10000000-0000-0000-0000-000000000002';

select is((select id from public.claim_command()), '10000000-0000-0000-0000-000000000001'::uuid, 'agent claims the live command');
select is_empty($$ select * from public.claim_command() $$, 'a claimed command is not handed out twice');
select is((select status from public.commands where id = '10000000-0000-0000-0000-000000000002'), 'expired',
  'stale commands expire instead of running');

-- ---------------------------------------------------------------- no role, no data
select pg_temp.act_as('00000000-0000-0000-0000-00000000000c', '');
select is((select count(*) from public.topics), 0::bigint, 'a user without a role sees nothing');

reset role;
set local role anon;
select throws_ok($$ select * from public.topics $$, '42501', null, 'anon has no access at all');

select * from finish();
rollback;
