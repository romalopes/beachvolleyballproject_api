# Database Backup & Restore — Beach Volleyball API

For system architecture and data lifecycles, see [System architecture and data lifecycles](architecture/architecture.md).

This runbook explains how to find encrypted PostgreSQL backups in Cloudflare R2,
verify and decrypt them, restore a disposable database, and recover the application.
Checked against this repository’s workflows on 9 October 2026. Live secrets and bucket configuration must be confirmed in the provider dashboards.

## Quick links

- [Cloudflare dashboard: select the backup bucket](https://dash.cloudflare.com/) (login and account access required).
- [Run or inspect Database Backup](https://github.com/romalopes/beachvolleyballproject_api/actions/workflows/database_backup.yml).
- [Run or inspect Database Restore Test](https://github.com/romalopes/beachvolleyballproject_api/actions/workflows/database_restore_test.yml).
- [Run or inspect Database Backup Freshness](https://github.com/romalopes/beachvolleyballproject_api/actions/workflows/database_backup_freshness.yml).
- [Repository Actions secrets](https://github.com/romalopes/beachvolleyballproject_api/settings/secrets/actions).
- [Set up and run a backup](#set-up-backups-and-run-the-first-backup).
- [Option 1: Restore using GitHub Actions](#option-1-restore-using-github-actions).
- [Option 2: Restore manually](#option-2-restore-manually).
- [Manual restore instructions](#manual-restore-to-a-new-database).
- [Production recovery and cutover](#production-recovery-and-cutover).

## Set up backups and run the first backup

1. **Identify the source.** In Render, inspect the API and worker `DATABASE_URL`
   privately. In the database provider, obtain a direct TLS connection URL to the
   same database. The workflow rejects hosts containing `-pooler`/`pooler.` and
   port 6543. Ensure the GitHub runner can reach the direct endpoint and the role
   can read every required schema/table. Never paste credentials into run logs.
2. **Create/select a private R2 backup bucket.** In Cloudflare → R2 Object Storage,
   create a dedicated bucket or select the intended existing backup bucket. Record
   its name and S3 API endpoint. No public URL is required.
3. **Create bucket-scoped S3 credentials.** Give the backup workflow object listing,
   read/head, upload and deletion access for its retention pruning. Manual download
   credentials can be read-only. Record the access key ID and secret securely.
4. **Generate the initial age pair** using [the key instructions below](#keep-the-original-private-key).
   Store its original private identity securely outside GitHub and outside the
   repository. Set `BACKUP_ENCRYPTION_RECIPIENT` to its public `age1...` key, and
   `BACKUP_ENCRYPTION_IDENTITY` to the matching private identity for restore tests.
   If backups already exist, retain their original keys; a new pair cannot decrypt them.
5. **Set repository Actions secrets** from the table below: the active provider’s
   source URL, four `R2_*` values, recipient and identity. Configure a separate
   disposable `*_RESTORE_TEST_DATABASE_URL` before running restore tests. Optional
   Slack configuration does not replace checking Actions failures directly.
6. **Review workflow defaults.** In all three workflow files set `DATABASE_PROVIDER`
   to the scheduled provider (`neon` currently). In backup/restore workflows also
   review the manual input default. Keep `SYSTEM_PREFIX=beachvolleyball`, and check
   `PG_CLIENT_MAJOR=18` supports the source server. Record `ENCRYPTION_KEY_ID=v1`
   with the archived key. Make the workflows available on the default branch for
   scheduled execution, and ensure repository Actions are enabled.
7. **Run a backup.** Open [Database Backup](https://github.com/romalopes/beachvolleyballproject_api/actions/workflows/database_backup.yml)
   → **Run workflow**, choose the intended branch and `database_provider`, then
   run. A manual provider choice affects only that run, not the schedules.
8. **Inspect every step.** Confirm connection/version validation, nonempty dump,
   encryption, checksum/metadata generation, all three uploads, and nonzero R2
   object sizes. Record the run URL and the exact `DAILY_PREFIX` from the upload
   log. On day 01 UTC, also confirm the monthly copy and sidecars. Upload size
   checks alone do not prove that an archive can be restored.
9. **Confirm the objects in R2.** Follow [the bucket instructions](#access-the-cloudflare-bucket-and-choose-a-backup).
   Check the provider/date and all three files. Do not publish or download a
   plaintext database to the repository.
10. **Prove recovery.** Run Option 1 below against the disposable target and validate
    representative application records. Then manually run [Backup Freshness](https://github.com/romalopes/beachvolleyballproject_api/actions/workflows/database_backup_freshness.yml).
    Freshness always uses its configured provider, with no dispatch override.
11. **Configure retention and monitoring.** Follow [retention and routine checks](#retention-and-routine-checks).
    Confirm the next scheduled backup/freshness runs and weekly restore test. Keep
    a record of the source identity, bucket/prefix, key ID and restore evidence,
    without recording secrets in this document.

This procedure creates encrypted backups through the repository workflow; the
workflow’s `pg_dump` reads source data. Its pruning step can delete expired daily
objects in the backup bucket, and the restore workflow overwrites its disposable target.

## Start here: the complete process in two options

Your backup is an age-encrypted PostgreSQL archive. Both options follow the same
sequence: **choose a backup → download → verify → decrypt → restore → validate**.
Choose one option; you do not need to perform both. Option 1 automates the restore
into a disposable hosted database. Option 2 runs the commands on your computer and
can restore a local database or a new hosted database for production recovery.

Before either option, have access to the backup, the original matching age private
key, and a separate target database. Neither option automatically changes the live
application's database connection. Uploaded files are in separate object storage and require
separate recovery if missing; they are not included in the database dump.

### Option 1: Restore using GitHub Actions

1. **Choose the snapshot.** Open the
   [Cloudflare dashboard](https://dash.cloudflare.com/),
   sign in, select R2 Object Storage and the bucket named by `R2_BUCKET`, then navigate to `beachvolleyball/postgresql/<provider>/`. Use `latest`
   for a routine restore test, or copy a specific `.dump.age` object key for a
   known-good snapshot. For an incident, choose a snapshot from before the problem.
2. **Create a disposable target.** In your database provider's console, create a
   separate database and copy its direct connection URL. Verify it is not the live
   database: this workflow overwrites matching objects in its target.
3. **Configure the target secret.** Open
   [GitHub Actions secrets](https://github.com/romalopes/beachvolleyballproject_api/settings/secrets/actions)
   and create/update `NEON_RESTORE_TEST_DATABASE_URL` or
   `SUPABASE_RESTORE_TEST_DATABASE_URL`, matching the selected database provider.
4. **Configure decryption and download access.** Set `BACKUP_ENCRYPTION_IDENTITY`
   to the matching original private identity (`AGE-SECRET-KEY-...`). Confirm
   `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_BUCKET`, and `R2_ENDPOINT`
   are present. An existing backup setup normally already has these R2 secrets.
   Do not generate a new key to decrypt an existing backup.
5. **Open the restore workflow.** Go to
   [Database Restore Test](https://github.com/romalopes/beachvolleyballproject_api/actions/workflows/database_restore_test.yml)
   and click **Run workflow**. Select the intended branch and `database_provider`.
6. **Select the backup and run.** Enter `latest` in `backup_prefix`, or paste the
   full key such as `beachvolleyball/postgresql/neon/2026/10/08/DAILY_2026-10-08_02-00-00.dump.age`
   (example only). Do not include `s3://` or `<R2_BUCKET>/`. Click **Run workflow**.
7. **Inspect the run.** Open the new run and its restore job. Check the selected
   backup key, download/checksum/decryption logs, target guard, restore output, and
   validation results. The workflow performs these operations for you; no manual
   download or local tools are needed for this option.
8. **Validate the restored application data.** Connect to the disposable database
   and inspect representative records and counts. Review the
   [workflow's validation limitations](#restore-through-github-actions-into-a-disposable-database)
   before declaring recovery successful. Save the run URL and backup key as evidence.
9. **Finish the test.** Keep the target disposable for scheduled tests; do not
   connect production to a database that the weekly restore test will overwrite.
   For actual recovery, use Option 2 with a dedicated replacement database and the
   [production cutover procedure](#production-recovery-and-cutover).

### Option 2: Restore manually

1. **Install the tools and open a private working directory.** Follow
   [step 1](#1-install-client-tools-and-prepare-a-private-directory) below to install
   `age` and PostgreSQL 18 clients, open Bash, and create `$RESTORE_DIR`. Install
   AWS CLI only if you want command-line downloads.
2. **Access the backup bucket.** Open the
   [Cloudflare dashboard](https://dash.cloudflare.com/),
   sign in, select R2 Object Storage and the bucket named by `R2_BUCKET`, and open the provider and date folders. Select a known-good snapshot.
3. **Download all three matching files.** Use the object's **... → Download** action
   for `.dump.age`, `.dump.age.sha256`, and `.dump.age.json`. Move them into
   `$RESTORE_DIR`, preserving their filenames. Alternatively, use the
   [AWS CLI download commands](#2-download-through-the-dashboard-or-aws-cli).
4. **Check the metadata and checksum.** Set `BACKUP_FILE` to the downloaded filename.
   Read its JSON metadata, then use the [verification commands](#3-verify-integrity-and-decrypt)
   to verify the downloaded file against the sidecar hash. Daily sidecars name the
   original runner archive rather than its R2 basename, so direct `-c` verification
   against the unmodified sidecar can report a missing file. Continue only on `OK`.
5. **Decrypt and inspect.** Set `AGE_IDENTITY_FILE` to the original matching private
   key file. Run the age decryption command to produce `backup.dump`, then
   `pg_restore --list backup.dump`. Stop if either command fails.
6. **Create a new empty target.** Create it in the provider console or on your local
   PostgreSQL server. Follow [step 4](#4-create-the-target-and-confirm-its-identity)
   to enter `RESTORE_DATABASE_URL` privately and check its database/user/server
   identity. Keep the app and workers disconnected from this target.
7. **Restore the archive.** Run the [step 5 command](#5-restore-schema-and-data):
   `pg_restore --dbname="$RESTORE_DATABASE_URL" --no-owner --no-acl --single-transaction --verbose backup.dump`.
   Wait for successful completion. Do not run seeds or `db:reset` over the restored data.
8. **Validate schema and data.** Follow [step 6](#6-validate-the-result) to inspect
   tables, user and migration counts, representative application records, and Rails
   migration status. Check compatibility with the application version you will run.
9. **Connect the intended application.** For a local copy, configure the development
   app to use the restored local database. For production recovery, follow the
   [cutover procedure](#production-recovery-and-cutover): pause writes/workers,
   update every service's `DATABASE_URL`, restart/redeploy, test, then resume traffic.
   Verify the configured Supabase/R2 attachment access separately.
10. **Complete recovery.** For production, update the backup source secret, run a
    fresh backup, and test recovery again using a separate disposable target.
    Record the recovered snapshot and checks. Remove temporary plaintext files and
    temporary key copies while retaining the securely archived original key.

The sections below provide the full commands, configuration details, and failure
handling for each step.

## Architecture and current configuration

| Workflow | Schedule (UTC) | What it does |
|---|---|---|
| [database_backup.yml](../.github/workflows/database_backup.yml) | Daily 02:00; manual dispatch | Custom-format `pg_dump`, age encryption, SHA-256 checksum, JSON metadata, R2 upload and object-size checks, daily pruning. |
| [database_restore_test.yml](../.github/workflows/database_restore_test.yml) | Sunday 03:00; manual dispatch | Downloads a backup, checks/decrypts it, restores a disposable database, checks tables and reports row counts. |
| [database_backup_freshness.yml](../.github/workflows/database_backup_freshness.yml) | Daily 06:00; manual dispatch | Fails if no backup exists or the newest encrypted dump is over 36 hours old. |

At the time of this documentation update, the workflows default to `neon`, support
`neon` and `supabase`, and pin PostgreSQL clients to **18** and age to **1.3.2**.
The backup command is `pg_dump --format=custom --no-owner --no-acl`; it reads the
source database without restoring or modifying application data.

**Confirm which database is actually being backed up.** The application reads
`DATABASE_URL`, while these workflows select `NEON_DATABASE_URL` or
`SUPABASE_DATABASE_URL`. Compare the host/database identity privately with the live
Render web and worker configuration. A provider label or successful workflow does
not prove it backed up the live database. There is no `render` provider option.

Schedules and object timestamps are UTC. Sydney is UTC+10 during standard time and
UTC+11 during daylight saving. Scheduled runs may be delayed; check actual run times.

## Access the Cloudflare bucket and choose a backup

1. Open the [Cloudflare dashboard](https://dash.cloudflare.com/).
2. Sign in to the Cloudflare account that owns the bucket. If navigating manually,
   open **R2 Object Storage**, then select the bucket configured in the workflow’s `R2_BUCKET` secret. Do not assume the Wine Words bucket is also this project’s bucket.
3. In the object list, navigate to `beachvolleyball/postgresql/neon/` or
   `beachvolleyball/postgresql/supabase/`, matching the backup workflow's selected provider.
4. Open the year/month/day prefix for daily backups, or look at the provider prefix
   for monthly backups. Open an object's **...** menu and select **Download**.
5. Download the encrypted dump and its two matching sidecars into one private local
   directory. Keep the original filenames; the verification steps below handle the daily sidecar’s different internal filename.

These dashboard steps follow [Cloudflare's download instructions](https://developers.cloudflare.com/r2/objects/download-objects/).
The bucket does not need public access. If the link is unavailable, verify your
Cloudflare account membership and permission to view/read the bucket.

### Object layout and file meanings

```text
<R2_BUCKET>/
  beachvolleyball/postgresql/<provider>/<YYYY>/<MM>/<DD>/DAILY_<timestamp>.dump.age
  beachvolleyball/postgresql/<provider>/<YYYY>/<MM>/<DD>/DAILY_<timestamp>.dump.age.sha256
  beachvolleyball/postgresql/<provider>/<YYYY>/<MM>/<DD>/DAILY_<timestamp>.dump.age.json
  beachvolleyball/postgresql/<provider>/MONTHLY_<timestamp>.dump.age
  beachvolleyball/postgresql/<provider>/MONTHLY_<timestamp>.dump.age.sha256
  beachvolleyball/postgresql/<provider>/MONTHLY_<timestamp>.dump.age.json
```

| File | Purpose |
|---|---|
| `.dump.age` | Encrypted, compressed PostgreSQL custom-format archive; decrypt before using `pg_restore`. |
| `.dump.age.sha256` | SHA-256 checksum of the encrypted file; daily sidecars reference the runner filename `database-<compact timestamp>.dump.age`, not the R2 basename. |
| `.dump.age.json` | Creation time, provider, dump/server versions, encryption key ID, and retention class. |

An **object key** starts with `beachvolleyball/`; it excludes the bucket name and `s3://`.
For example (illustrative timestamp):

```text
beachvolleyball/postgresql/neon/2026/10/08/DAILY_2026-10-08_02-00-00.dump.age
```

Choose the newest **known-good** snapshot for recovery. For accidental deletion or
corruption, choose one from before the incident, even if a newer backup exists.
Daily and monthly dumps are full snapshots, not incremental chains; restore one.
Changes after its snapshot are absent. The `latest` workflow input chooses by R2
`LastModified`, which is not a guarantee of application-level correctness.

## Access, credentials, and encryption keys

Add workflow secrets under **Settings → Secrets and variables → Actions** in the
[repository settings](https://github.com/romalopes/beachvolleyballproject_api/settings/secrets/actions).

| Secret | Purpose |
|---|---|
| `NEON_DATABASE_URL` | Source connection for the `neon` selection. Use a direct URL with TLS, not a pooler. |
| `SUPABASE_DATABASE_URL` | Source connection for the `supabase` selection; same connection requirements. |
| `NEON_RESTORE_TEST_DATABASE_URL` | Direct connection to a disposable Neon restore database. Never production. |
| `SUPABASE_RESTORE_TEST_DATABASE_URL` | Direct connection to a disposable Supabase restore database. Never production. |
| `BACKUP_ENCRYPTION_RECIPIENT` | age public key (`age1...`) used to encrypt new backups. |
| `BACKUP_ENCRYPTION_IDENTITY` | Matching age private key (`AGE-SECRET-KEY-...`) used by the restore workflow. |
| `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY` | R2 S3 API credentials. |
| `R2_BUCKET` | Actual private backup bucket name; confirm in Cloudflare and the workflow secret. |
| `R2_ENDPOINT` | Bucket's S3 API endpoint, copied from Cloudflare; not the dashboard URL. |
| `SLACK_WEBHOOK_URL` | Optional failure notification configuration. Check Actions directly as well. |

For manual downloads via the dashboard you need Cloudflare access. CLI downloads
need R2 credentials with object-read access to the bucket; they do not need deletion
permissions. See [R2 API credentials](https://developers.cloudflare.com/r2/api/tokens/).
Current [production configuration](../config/environments/production.rb) selects
`:supabase`; [development](../config/environments/development.rb) selects
`:cloudflare_r2`. Confirm the deployed revision if this has changed. Production
media uses `SUPABASE_S3_ACCESS_KEY_ID`, `SUPABASE_S3_SECRET_ACCESS_KEY`,
`SUPABASE_S3_REGION`, `SUPABASE_S3_BUCKET_NAME`, and `SUPABASE_PROJECT_REF`.
R2 media uses `CLOUD_FLARE_R2_BUCKET`, `CLOUD_FLARE_R2_ACCESS_KEY_ID`,
`CLOUD_FLARE_R2_ACCESS_KEY`, and `CLOUD_FLARE_R2_ENDPOINT` (or `CLOUD_FLARE_R2_REF`).
These media settings are distinct from the workflow’s `R2_*` backup settings.
Selecting a PostgreSQL provider does not select the attachment storage provider.

### Keep the original private key

Store the original age identity file in a secure password manager or offline backup,
separate from the dumps. GitHub Actions secrets are not a way to retrieve a previously
saved private key for local use. A configured restore workflow can still use its secret.

**A newly generated key cannot decrypt an old backup.** The public recipient alone
is insufficient. If all copies of the matching private key are lost, the encrypted
backup cannot be recovered.

For initial setup or planned rotation only, generate a new pair outside the repository:

```bash
umask 077
age-keygen -o /secure/path/beachvolleyball-age-key.txt
age-keygen -y /secure/path/beachvolleyball-age-key.txt
```

The second command prints the public recipient. Put that in
`BACKUP_ENCRYPTION_RECIPIENT` and the private identity in `BACKUP_ENCRYPTION_IDENTITY`.
On rotation, update `ENCRYPTION_KEY_ID` in the backup workflow and retain old identities
for retained backups. The metadata key ID helps choose the correct archived identity.
See the [official age instructions](https://github.com/FiloSottile/age).

## Restore through GitHub Actions into a disposable database

This is the quickest way to exercise the existing recovery pipeline. It does not
switch the application to the restored database.

1. Provision a separate disposable database with the chosen provider. Confirm its
   host and database identity independently of its display name; use a direct URL.
2. Set `NEON_RESTORE_TEST_DATABASE_URL` or `SUPABASE_RESTORE_TEST_DATABASE_URL` to it.
   Ensure R2 secrets and the matching `BACKUP_ENCRYPTION_IDENTITY` are configured.
3. Open [Database Restore Test](https://github.com/romalopes/beachvolleyballproject_api/actions/workflows/database_restore_test.yml)
   and select **Run workflow**, using the branch containing the intended workflow.
4. Select `database_provider`. For `backup_prefix`, use `latest` or paste the full
   object key ending in `.dump.age`, without the bucket name. Despite the input's
   name, an explicit value must identify a file, not just a folder prefix.
5. Inspect every restore/validation step and the summary. Record the chosen key,
   run URL, restore duration, and validation result.

**The workflow runs `pg_restore --clean --if-exists`: it drops/recreates matching
objects in the target.** Use only an expendable target. Its guard rejects empty
URLs, exact matches with configured production URLs, and database names containing
`prod`. Different URLs/credentials can still reach the same database, so the guard
is not proof of isolation. Do not bypass it for production recovery.

Current validation checks the archive structure and at least five user tables.
It reports `users` and `schema_migrations` counts, but missing results for those
queries do not necessarily fail the job. The checksum step also permits a missing
sidecar, relying on age authentication; the final summary still says SHA-256 was
verified. Read the step logs rather than treating the summary as complete proof.
The restore is not currently wrapped in a single transaction, so a failed test can
leave partial changes in the disposable database. Validate application data separately.

## Manual restore to a new database

Use this path for a local copy or a replacement hosted database. Start with a new,
empty database and keep applications/workers disconnected until validation finishes.
Commands below run in Bash; replace example paths and object keys before use.

### 1. Install client tools and prepare a private directory

On macOS with Homebrew installed:

```bash
brew install age awscli postgresql@18
export PATH="$(brew --prefix postgresql@18)/bin:$PATH"
bash
```

AWS CLI is optional if downloading through the dashboard. Installing PostgreSQL tools
does not require starting a local server when restoring to a hosted database.
See [Homebrew PostgreSQL 18](https://formulae.brew.sh/formula/postgresql@18).
On Linux, install age, AWS CLI if needed, and PostgreSQL 18 client tools using the
appropriate distribution packages or official installers.

In the Bash session:

```bash
set -euo pipefail
umask 077
RESTORE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/beachvolleyball-restore.XXXXXX")
cd "$RESTORE_DIR"
pwd
age --version
pg_restore --version
psql --version
```

Use this directory for all three downloaded files. Use a PostgreSQL 18 restore client
for the current workflow's dumps and inspect the metadata for older archives.
A client capable of reading the archive does not guarantee compatibility with an
older target server; use a compatible target and test extensions/provider permissions.

### 2. Download through the dashboard or AWS CLI

For dashboard downloads, follow the [bucket instructions above](#access-the-cloudflare-bucket-and-choose-a-backup)
and move the three original files into `$RESTORE_DIR`.

Alternatively, configure a dedicated AWS CLI profile using the R2 access key ID and
secret access key at the interactive prompts. Set region to `auto` and output to `json`:

```bash
aws configure --profile beachvolleyball-r2
R2_BUCKET='<your-backup-bucket>'
R2_ENDPOINT='https://<your-account-id>.r2.cloudflarestorage.com'

aws --profile beachvolleyball-r2 --endpoint-url "$R2_ENDPOINT" \
  s3 ls "s3://$R2_BUCKET/beachvolleyball/postgresql/neon/" --recursive
```

Confirm the endpoint against the bucket's S3 API endpoint in Cloudflare (and the
workflow secret), and change the provider prefix if needed. This uses Cloudflare's
S3-compatible API, not an AWS-hosted bucket. See [Cloudflare AWS CLI setup](https://developers.cloudflare.com/r2/examples/aws/aws-cli/).

Choose the exact key from the listing, then download its matching files:

```bash
# Example only: replace with an existing key from your bucket.
BACKUP_KEY='beachvolleyball/postgresql/neon/2026/10/08/DAILY_2026-10-08_02-00-00.dump.age'
BACKUP_FILE="${BACKUP_KEY##*/}"

for suffix in '' '.sha256' '.json'; do
  aws --profile beachvolleyball-r2 --endpoint-url "$R2_ENDPOINT" \
    s3 cp "s3://$R2_BUCKET/${BACKUP_KEY}${suffix}" "${BACKUP_FILE}${suffix}"
done
```

### 3. Verify integrity and decrypt

If you downloaded through the dashboard, set `BACKUP_FILE` to the actual encrypted
filename first. The CLI instructions already set it. Do not rename downloaded files.

```bash
# Example only; use your actual filename.
BACKUP_FILE='DAILY_2026-10-08_02-00-00.dump.age'
cat "${BACKUP_FILE}.json"

# Preserve the original sidecar, but verify its hash against our downloaded name.
# Daily R2 objects were renamed after the workflow generated their checksum.
EXPECTED_HASH=$(awk 'NR == 1 {print $1}' "${BACKUP_FILE}.sha256")
[[ "$EXPECTED_HASH" =~ ^[[:xdigit:]]{64}$ ]] || { echo 'Invalid checksum sidecar'; exit 1; }
printf '%s  %s\n' "$EXPECTED_HASH" "$BACKUP_FILE" > checksum.local.sha256
if command -v sha256sum >/dev/null 2>&1; then
  sha256sum -c checksum.local.sha256
else
  shasum -a 256 -c checksum.local.sha256
fi
# Must report OK. Never calculate a replacement expected hash from the dump.

AGE_IDENTITY_FILE='/absolute/path/to/original-age-key.txt'
chmod 600 "$AGE_IDENTITY_FILE"
age --decrypt --identity "$AGE_IDENTITY_FILE" \
  --output backup.dump "$BACKUP_FILE"

pg_restore --list backup.dump > toc.txt
head -n 30 toc.txt
```

Confirm the metadata's provider, timestamp, versions, and encryption key ID are the
ones you intended. Stop on checksum or decryption errors. If the sidecar is missing,
investigate the backup run before proceeding; these manual steps require it.

The decrypted `backup.dump` contains sensitive database content. Keep it outside the
repository. Do not run `psql -f` on it: it is a custom archive, not a plain SQL file.

### 4. Create the target and confirm its identity

Create an empty database through your provider's console. Use its direct connection
string and required TLS options. The database must already exist; the restore command
below does not create it. Use an account allowed to create the required objects.

For a local PostgreSQL server that is already running, an alternative is:

```bash
createdb beachvolleyball_restore
# The local target URL can be postgresql:///beachvolleyball_restore
```

Enter the target URL privately rather than putting its password in shell history:

```bash
read -r -s -p 'New empty database URL: ' RESTORE_DATABASE_URL
printf '\n'
export RESTORE_DATABASE_URL

psql "$RESTORE_DATABASE_URL" -X -v ON_ERROR_STOP=1 \
  -c 'SELECT current_database(), current_user, inet_server_addr(), inet_server_port();' \
  -c 'SHOW server_version;' \
  -c '\dt'
```

Check this identity against the new database in the provider console before continuing.
A hosted project may contain provider-managed schemas; do not drop them to make it
empty. Provider-owned schemas/extensions may require a provider-specific restore plan.

### 5. Restore schema and data

```bash
pg_restore \
  --dbname="$RESTORE_DATABASE_URL" \
  --no-owner \
  --no-acl \
  --single-transaction \
  --verbose \
  backup.dump
```

`--no-owner` and `--no-acl` avoid restoring original ownership/grants. Objects are
owned by the restoring role; arrange any application-role permissions separately.
`--single-transaction` makes the operation atomic and implies exit on error.
See [PostgreSQL pg_restore options](https://www.postgresql.org/docs/18/app-pgrestore.html).

This command intentionally targets an empty database. For a repeat restore into a
**disposable** target, recreate that target or deliberately add `--clean --if-exists`.
Those flags drop matching objects and their data; they do not remove unrelated objects.
Do not use them casually against the live database. Do not run Rails `db:reset`,
`db:schema:load`, or seeds as part of restoring this full dump.

### 6. Validate the result

```bash
psql "$RESTORE_DATABASE_URL" -X -v ON_ERROR_STOP=1 \
  -c '\dt' \
  -c 'SELECT count(*) AS users_count FROM users;' \
  -c 'SELECT count(*) AS migration_count FROM schema_migrations;'
```

Compare meaningful application records and counts with the chosen snapshot's expected
state. Inspect people, player/coach profiles, organisations, drills, training sessions,
assessments, associations, and representative users;
nonzero table counts alone do not establish recovery correctness.

From the `beachvolleyballproject_api` directory, with application dependencies configured:

```bash
DATABASE_URL="$RESTORE_DATABASE_URL" RAILS_ENV=production bin/rails db:migrate:status
```

For a local development copy use `RAILS_ENV=development`. Check pending migrations
against the code version being deployed. Only after reviewing compatibility, apply
required migrations to the replacement database with `bin/rails db:migrate` using
the same explicit `DATABASE_URL` and `RAILS_ENV`. Do not seed automatically.

## Production recovery and cutover

1. Record the incident time and choose a known-good snapshot. Record its key and
   expected data-loss window; this workflow supplies snapshots, not point-in-time recovery.
2. Pause application writes, background workers, scheduled jobs, and integrations
   before cutover. If the old database is reachable, preserve a separate current
   backup for investigation or reconciliation; do not overwrite the selected snapshot.
3. Provision a replacement database, restore using the manual steps, and validate it.
   Keep the old database available for rollback. A restore test is evidence, not an
   automatic production failover.
4. Verify migrations, role permissions, required extensions, and storage access with
   the intended application version. Review restored job tables before starting
   workers to avoid replaying jobs with external effects.
5. Update `DATABASE_URL` for every web/worker service and redeploy or restart them.
   Check all four Rails connections (primary/cache/queue/cable); the current
   `config/database.yml` points all of them at `DATABASE_URL`.
6. Smoke-test login and representative read/write operations on people, organisations,
   drills, training sessions, and attachments. Resume traffic and workers only after validation.
7. Update the backup source secret to the new live database, run a fresh backup, then
   run restore and freshness checks. The restore-test target remains disposable.
8. Record the backup key, restore/cutover times, validation evidence, and changes made.
   If rollback is needed after new writes were accepted, reconcile those writes before
   returning to the old database; simply switching URLs can lose new data.

After validation, remove temporary plaintext and any temporary copy of the identity:

```bash
rm -f "$RESTORE_DIR/backup.dump" "$RESTORE_DIR/toc.txt"
unset RESTORE_DATABASE_URL
```

Do not delete your archived recovery key. Remove any extra copies from Downloads or
other working folders. File deletion or `shred` is not guaranteed secure erasure on
SSDs, snapshots, or copy-on-write filesystems; use protected storage from the start.

## Retention and routine checks

The backup workflow prunes `DAILY_` objects older than 14 days for its selected provider.
It writes a `MONTHLY_` copy on the first day of the month and never prunes monthly
objects itself. The intended monthly retention is 12 months; confirm bucket lifecycle
rules actually implement it. Workflow success does not prove lifecycle configuration.

In the bucket, open **Settings → Object Lifecycle Rules**. R2 rules match object
**prefixes**, not filename substrings. A broad 14-day rule on
`beachvolleyball/postgresql/neon/` would also delete monthly snapshots. With the current
layout, daily rules can target year prefixes such as `beachvolleyball/postgresql/neon/2026/`
(and must be maintained for new years), while monthly rules can target
`beachvolleyball/postgresql/neon/MONTHLY_`. Apply equivalent rules for other used providers,
include sidecars, and verify matching keys before enabling deletion. See
[Cloudflare lifecycle rules](https://developers.cloudflare.com/r2/buckets/object-lifecycles/).

Check backup and freshness run failures daily and restore-test results weekly. Keep
recovery credentials and old encryption keys available, and periodically rehearse the
manual restore and application validation. Check notifications actually arrive;
Actions job status is the primary evidence. The current Slack payload command places
`MESSAGE="$MESSAGE"` after the Python command, rather than exporting it to that
process; do not rely on Slack alerts until delivery is tested and this is corrected.
Measure restore duration during rehearsals.

## Switching providers

1. Configure the new provider's source and disposable-target secrets with direct URLs.
2. Change `DATABASE_PROVIDER` in all three workflows (`neon` or `supabase`).
3. Run a manual backup for the new provider and restore that backup into its test target.
4. Run freshness monitoring and confirm the deployed app and backup source agree.

A manual provider override applies only to that run. It does not change the scheduled
default or the freshness workflow. Preserve old provider backups and their keys for
as long as their retention/recovery requirements apply.

## Backup scope and limitations

The archive contains PostgreSQL schema/data, including Rails migration history,
Active Storage database records, and Solid Queue/Cache/Cable tables when they are
in the selected database. It does **not** include uploaded file bytes, application
secrets, deployment settings, or cluster-wide roles. Ownership/grants are not
restored by the documented commands.

The bucket named by workflow `R2_BUCKET` contains encrypted database snapshots.
Production attachments currently live in the Supabase bucket identified by
`SUPABASE_S3_BUCKET_NAME`; development uses the R2 media bucket identified by
`CLOUD_FLARE_R2_BUCKET` unless you selected local disk. Arrange separate media
backups and recovery, preserving object keys so restored Active Storage records
can locate their files. Verify the deployed storage service, credentials and
representative attachment downloads alongside database checks.

## Troubleshooting

| Symptom | What to check |
|---|---|
| Bucket link fails / access denied | Correct Cloudflare account and bucket permissions. For CLI access, use R2 S3 credentials and the bucket's S3 endpoint. |
| No backups / `NoSuchKey` | Provider prefix, exact object key, retention, and backup run logs. Do not include the bucket name in `backup_prefix`. |
| Checksum reports missing file | Daily sidecars reference `database-<timestamp>.dump.age`. Use the normalized verification steps above; also check for browser-added `(1)` suffixes. |
| Checksum mismatch | Stop; download the matching dump/sidecar again and investigate. Do not replace the expected checksum with a newly calculated one. |
| age cannot decrypt | Correct private identity for the JSON key ID; public recipient and newly generated keys cannot decrypt older backups. |
| `unsupported version ... in file header` | Check `pg_restore --version` and PATH; use the client matching the dump version, currently 18. |
| Dump client older than source server | Update `PG_CLIENT_MAJOR` in backup and restore workflows together after checking compatibility. |
| Connection fails / pooler rejected | Direct host, TLS settings, credentials, network reachability, firewall/allowlist, and provider connection limits. |
| Restore guard aborts | Target must be separate and disposable; do not disguise production to bypass the guard. |
| Existing relations / duplicate keys | Use a fresh target. A failed nontransactional workflow run may have left partial objects. |
| Missing role, extension, or permission | Inspect the first restore error. Check target ownership/extension support and provider-managed schemas; do not ignore errors. |
| Restore is green but records are wrong | Verify selected source, snapshot date, and business data; current automated validation is limited. |
| Attachments fail after recovery | Check the selected storage service (currently Supabase in production), bucket, endpoint, credentials and referenced object keys. Restore missing media from its separate backup; database metadata does not contain uploaded file bytes. |
