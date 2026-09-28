# ShortsOps

Mobile control room for the facts-shorts pipeline: a Flutter app, a Supabase backend, and a
small agent on the machine that runs the pipeline.

```
 Flutter app ──(Auth + RLS)──►  Supabase  ◄──(outbound only)── agent (laptop)
   read state, send commands     Postgres mirror + command queue   files → tables, commands → facts-shorts CLI
   live updates (Realtime)       Realtime · Storage                heartbeat every 60 s
```

The laptop never accepts inbound connections. The pipeline keeps its own JSON files as the
source of truth and runs unchanged (cron included) when the agent or Supabase is down; the
agent mirrors those files into Supabase and turns app commands into fixed facts-shorts CLI calls.

| Path | What it is |
|---|---|
| `supabase/migrations/` | Schema, row-level security, `claim_command()`, Realtime, private `previews` bucket |
| `supabase/tests/` | pgTAP tests proving what the owner, the agent and everyone else can do |
| `agent/` | Python agent: mirror, command runner, heartbeat; systemd unit in `agent/deploy/` |
| `app/` | Flutter app (Riverpod, go_router, supabase_flutter); Android and web |

## Security model

- Two roles, stored in `app_metadata` (users cannot edit it): `owner` (you, in the app) and `agent`
  (the laptop). Public sign-up is disabled; both accounts are created by hand.
- No table is exposed to the Data API by default; each is granted explicitly, and every table has RLS.
- The owner reads everything and may only create or cancel commands. The agent writes the mirror
  and finishes commands but can never create one. Anyone else sees nothing.
- The agent uses the publishable key plus its own login, never the `service_role`/secret key.
  YouTube and stock-footage credentials stay on the laptop.
- Commands are an allowlist validated twice (database check constraint, then a strict pydantic
  model per type) and become an argv list, never a shell string. They expire (default 1 h, max 24 h),
  long ones share the cron run's lock so they never overlap it, and research/stats are rate limited.

## Setup

### 1. Database

```bash
supabase login                      # opens the browser
supabase link --project-ref <ref>   # asks for the database password; type it, don't store it
supabase db push                    # applies supabase/migrations
```

In the dashboard: **Authentication > Sign In / Providers**, turn off **Allow new users to sign up**.

### 2. Create the two users

**Authentication > Users > Add user** twice (auto-confirm): your own email, and an agent address
such as `agent+shortsops@<your-domain>` with a long generated password. Then in the SQL editor:

```sql
update auth.users set raw_app_meta_data = raw_app_meta_data || '{"role": "owner"}' where email = '<you>';
update auth.users set raw_app_meta_data = raw_app_meta_data || '{"role": "agent"}' where email = '<agent>';
```

### 3. Agent

```bash
cd agent
uv sync
cp .env.example .env && chmod 600 .env    # fill in URL, publishable key, agent login
mkdir -p ~/.config/systemd/user
cp deploy/shortsops-agent.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now shortsops-agent
loginctl enable-linger "$USER"            # keep it running without an open session
journalctl --user -u shortsops-agent -f   # watch it sync
```

### 4. App

The app takes the project URL and publishable key at build time; both are public by design
(access is decided by RLS and the signed-in user's role), but `env.json` stays out of git anyway.

```bash
cd app
cp env.example.json env.json                           # fill in URL and publishable key
flutter run --dart-define-from-file=env.json           # device, emulator or -d web-server
flutter build apk --release --split-per-abi --target-platform android-arm64 \
  --dart-define-from-file=env.json                     # -> build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

Release builds are signed by the keystore that `android/key.properties` (gitignored) points to;
without that file they fall back to the debug key and are not for distribution. Create one with:

```bash
keytool -genkeypair -keystore ~/.android-keys/shortsops-upload.jks -storetype PKCS12 \
  -alias upload -keyalg RSA -keysize 4096 -validity 10000
# android/key.properties: storeFile=<path>, storePassword=..., keyAlias=upload, keyPassword=...
```

Back up the keystore and its password together: Android only installs an update over an existing
install when both are signed with the same key.

Sign in with the owner account. Tabs: **Status** (laptop online/offline, daily run, quota, disk,
pause switch, schedule, recent events), **Queue** (reorder, build now, skip/restore, return stuck
topics, add your own, research more), **Videos** (scheduled and live with views; live videos still
private are flagged), **Activity** (live run steps and every command's outcome).

## Commands the app can send

| Type | Runs | Notes |
|---|---|---|
| `add_topic {text}` | `topic add` | 5-200 chars, queued first |
| `reorder_topics {ids}` | `topic reorder` | listed ids move to the front |
| `skip_topic`, `restore_topic`, `reset_stuck {id}` | `topic skip/restore/reset` | reset fixes `building`/`failed` |
| `research {n}` | `research -n` | 1-20, once per hour |
| `make {topic_id?}` | `make` | takes the pipeline lock |
| `approve_upload`, `publish_now {build}` | `upload DIR [--now]` | confidence >= 70 still enforced |
| `rebuild {build}` | `rebuild DIR` | |
| `refresh_stats` | `stats` | once per 30 min |
| `pause`, `resume` | `pause/resume` | `run_daily.sh` skips while paused |
| `cleanup {days}` | `cleanup --days` | deletes heavy files of older published Shorts |
| `reschedule`, `update_config` | - | reserved; the agent rejects them until implemented |

## Development

```bash
supabase start -x studio,imgproxy,vector,logflare,supavisor,mailpit,edge-runtime
supabase test db                    # RLS tests
cd agent && uv run pytest && uv run ruff check .
```
