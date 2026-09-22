# Database Backup & Restore — Beach Volleyball API

V2 backup system. Single active provider (Neon OR Supabase), daily
encrypted backups to Cloudflare R2, weekly restore proof, daily
freshness monitoring.

## Architecture

- `database_backup.yml` — daily 02:00 UTC + manual dispatch.
  `pg_dump --format=custom --no-owner --no-acl` (read-only) against the
  single active provider, age authenticated encryption, SHA-256 of the
  encrypted file, JSON metadata sidecar, upload to R2, head-object
  verification, DAILY_ pruning safety net.
- `database_restore_test.yml` — weekly Sunday 03:00 UTC + manual
  dispatch (`latest` or a specific `.dump.age` key). Download,
  checksum verify, age decrypt, `pg_restore --list` sanity, technical
  prod-target guard, restore into a disposable database, schema + data
  validation, plaintext shredding.
- `database_backup_freshness.yml` — daily 06:00 UTC. Fails (and
  notifies) if the newest `.dump.age` is older than 36 hours.

## R2 layout

```
<bucket>/beachvolleyball/postgresql/<provider>/<YYYY>/<MM>/<DD>/DAILY_<ts>.dump.age
<bucket>/beachvolleyball/postgresql/<provider>/<YYYY>/<MM>/<DD>/DAILY_<ts>.dump.age.sha256
<bucket>/beachvolleyball/postgresql/<provider>/<YYYY>/<MM>/<DD>/DAILY_<ts>.dump.age.json
<bucket>/beachvolleyball/postgresql/<provider>/MONTHLY_<ts>.dump.age (+ .sha256, .json)
```

Retention: DAILY_ kept 14 days (workflow safety net; R2 lifecycle rules
are the primary mechanism — configure: delete DAILY_ after 14 days,
keep MONTHLY_ for 12 months). MONTHLY_ snapshots are written on the 1st
of each month and are never deleted by the workflow.

## Secrets (GitHub repo secrets, never committed)

| Secret | Purpose |
|---|---|
| `NEON_DATABASE_URL` | Direct Neon URL (`sslmode=require`, non-pooler). Poolers are rejected by the workflow. |
| `SUPABASE_DATABASE_URL` | Direct Supabase URL (same rules). |
| `NEON_RESTORE_TEST_DATABASE_URL` | Disposable Neon restore target. Never production. |
| `SUPABASE_RESTORE_TEST_DATABASE_URL` | Disposable Supabase restore target. Never production. |
| `BACKUP_ENCRYPTION_RECIPIENT` | age public key (`age1...`) used to encrypt. Generate: `age-keygen`. |
| `BACKUP_ENCRYPTION_IDENTITY` | age private key (`AGE-SECRET-KEY-...`) used only by restore tests. |
| `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_BUCKET`, `R2_ENDPOINT` | Cloudflare R2 destination. |
| `SLACK_WEBHOOK_URL` (optional) | Failure/freshness alerts. Steps are skipped if unset. |

Key rotation: generate a new age keypair, update both secrets, bump
`ENCRYPTION_KEY_ID` in `database_backup.yml`. Old backups remain
decryptable with the old identity — archive it offline with its key id.

## Switching providers (Neon <-> Supabase)

1. Ensure the target provider's `*_DATABASE_URL` secret exists and is a
   direct (non-pooler) URL.
2. Change `DATABASE_PROVIDER` in all three workflow files
   (`database_backup.yml`, `database_restore_test.yml`,
   `database_backup_freshness.yml`).
3. Run `database_backup.yml` manually with the new provider selected,
   then run `database_restore_test.yml` against the new backup.

## Manual operations

Trigger `database_backup.yml` via workflow dispatch (optionally
overriding the provider). Trigger `database_restore_test.yml` with
`latest` or a full R2 key (`beachvolleyball/postgresql/.../*.dump.age`).
To restore locally: download the three files, `sha256sum -c`,
`age --decrypt --identity <keyfile>`, then `pg_restore --list` and
`pg_restore --clean --if-exists --no-owner --no-acl --dbname=<disposable>`.

Disaster recovery order: provision a new database, restore the newest
MONTHLY_ (or newest DAILY_), run `bin/rails db:migrate:status` to
confirm the schema, point the app at the new URL, verify.

## What is NOT backed up

`pg_dump` covers PostgreSQL only. Active Storage (Supabase storage in
production — see `config/storage.yml`) and any R2 media buckets are NOT
included. Media needs its own bucket replication/versioning story.

## Troubleshooting

- pg_dump version error: bump `PG_CLIENT_MAJOR` (currently 17) to match
  the server major shown in the version-validation step.
- Pooler rejection: use the provider's direct connection string.
- age errors: confirm the recipient is an `age1...` public key and the
  identity matches; `AGE_VERSION` is pinned (currently 1.3.2).
- Restore guard aborts: the target equals a production URL or its name
  looks like prod — use a disposable database.
