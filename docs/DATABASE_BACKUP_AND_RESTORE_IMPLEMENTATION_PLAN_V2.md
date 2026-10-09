# Database Backup and Restore Implementation Plan V2

## Objective

Implement a production-ready PostgreSQL backup and restore system for the application.

The system must support both **Neon** and **Supabase**, while keeping the provider-specific logic isolated so the database provider can be changed later without redesigning the backup system.

The implementation must provide:

- Automated daily database backups.
- Encrypted backups stored in the existing Cloudflare R2 bucket.
- Direct PostgreSQL connections suitable for `pg_dump`.
- PostgreSQL client/server version validation.
- Authenticated encryption.
- SHA-256 corruption/integrity verification.
- Daily and longer-term retention.
- A separate automated restore-test workflow.
- Technical protection against restoring over production.
- Weekly restore testing.
- Backup freshness monitoring.
- Failure notifications.
- Operational documentation.
- Explicit documentation that PostgreSQL backups do not include Active Storage/media files.

---

# 1. Existing infrastructure

The following infrastructure already exists.

**Do not recreate it.**

- GitHub Actions environment.
- GitHub Actions secrets.
- Cloudflare R2 bucket for database backups.

Before implementing anything:

1. Inspect the repository.
2. Inspect existing GitHub Actions workflows.
3. Inspect existing backup-related configuration.
4. Identify the actual existing secret names.
5. Reuse the existing infrastructure wherever possible.

Do not create duplicate secrets unnecessarily.

---

# 2. Target architecture

Implement the following architecture:

```text
                         GitHub Actions
                              |
              +---------------+---------------+
              |                               |
         Daily Backup                    Weekly Restore Test
              |                               |
      Neon OR Supabase                  Latest R2 Backup
              |                               |
      Direct PostgreSQL                  Verify checksum
         connection                            |
              |                              Decrypt
           pg_dump                              |
              |                             pg_restore
      PostgreSQL custom                          |
          format                         Disposable DB
              |                               |
  Authenticated encryption                Validate schema
              |                           + representative data
          SHA-256                              |
              |                              Cleanup
              v
       Cloudflare R2
              |
       Retention policy
              |
       Freshness monitoring
```

Create separate workflows:

```text
.github/workflows/database_backup.yml
.github/workflows/database_restore_test.yml
.github/workflows/database_backup_freshness.yml
```

If the repository already has an appropriate monitoring workflow, the freshness check may be integrated there instead of creating a third workflow.

---

# 3. Database provider configuration

Support:

```text
neon
supabase
```

Use an explicit configuration mechanism such as:

```text
DATABASE_PROVIDER=neon
```

or:

```text
DATABASE_PROVIDER=supabase
```

The manual `workflow_dispatch` should allow the provider to be selected where practical.

Keep provider selection simple.

Do not create unnecessarily complicated GitHub Actions expressions for selecting secrets.

Provider-specific logic should be isolated to:

1. Provider selection.
2. Direct database connection configuration.
3. Optional disposable restore database creation.
4. Optional disposable restore database deletion.

The generic backup logic must be shared.

---

# 4. Direct database connections

`pg_dump` must use a **direct PostgreSQL connection**.

Do not assume connection poolers support database dump operations.

## Neon

Prefer the direct Neon database URL.

Do not use a hostname containing:

```text
-pooler
```

unless it has been explicitly verified to work correctly with `pg_dump`.

## Supabase

Prefer the direct PostgreSQL connection.

Do not assume the Supabase transaction pooler on port:

```text
6543
```

is appropriate for `pg_dump`.

Document this requirement clearly.

The workflow should validate the connection configuration and fail clearly when an unsuitable connection is detected.

---

# 5. PostgreSQL client version

Pin the PostgreSQL client version used by GitHub Actions.

Do not rely blindly on the version preinstalled on the GitHub runner.

At the beginning of the backup job:

```bash
pg_dump --version
```

and:

```bash
psql "$DATABASE_URL" -Atc "SELECT version();"
```

Record both versions.

Validate that the `pg_dump` client is compatible with the PostgreSQL server.

If compatibility cannot be established, fail clearly rather than creating a potentially unreliable backup.

The restore workflow must use the same compatible PostgreSQL client strategy.

---

# 6. Daily backup workflow

Create:

```text
.github/workflows/database_backup.yml
```

The workflow must:

- Run once per day at a fixed UTC time.
- Support `workflow_dispatch`.
- Allow provider selection.
- Prevent overlapping backup jobs.
- Never expose secrets.
- Never use `set -x`.

Recommended flow:

```text
Checkout
    ↓
Install pinned PostgreSQL client
    ↓
Resolve provider
    ↓
Resolve direct database URL
    ↓
Validate database connection
    ↓
Validate PostgreSQL versions
    ↓
Create pg_dump custom-format backup
    ↓
Encrypt backup
    ↓
Generate SHA-256
    ↓
Upload backup/checksum/metadata to R2
    ↓
Verify uploaded objects
    ↓
Report success/failure
```

Use concurrency protection similar to:

```yaml
concurrency:
  group: database-backup
  cancel-in-progress: false
```

Do not allow a new scheduled backup to cancel an existing backup while it is running.

---

# 7. PostgreSQL dump format

Use:

```bash
pg_dump --format=custom
```

Do not add a second gzip compression step.

`pg_dump -Fc` already compresses the dump.

Use:

```text
database
    ↓
pg_dump -Fc
    ↓
authenticated encryption
```

instead of:

```text
pg_dump -Fc
    ↓
gzip
    ↓
encryption
```

unless there is a specific measured reason to do otherwise.

---

# 8. Temporary plaintext backup

Minimize the lifetime of the unencrypted dump.

If a temporary plaintext dump is required:

- Store it only in the GitHub Actions temporary workspace.
- Restrict permissions.
- Encrypt it immediately.
- Delete it immediately after encryption.
- Delete decrypted files during cleanup.
- Ensure cleanup also runs after failures.

Never upload an unencrypted database dump to R2.

Never commit a database dump to Git.

---

# 9. Database credential exposure

Avoid exposing the complete database URL in process arguments where practical.

The implementation should use safe PostgreSQL authentication mechanisms where appropriate, such as:

- environment variables
- `.pgpass`
- explicit host/database/user parameters

Do not print the database URL.

Do not use:

```bash
set -x
```

Do not echo secrets for debugging.

---

# 10. Authenticated encryption

Do **not** use AES-256-CBC by itself.

CBC does not provide authenticated encryption.

Prefer an authenticated encryption tool such as:

```text
age
```

or another authenticated encryption mechanism that can be reliably installed and pinned in GitHub Actions.

The encryption key must be stored in GitHub Actions Secrets.

The encryption key must never be:

- committed
- printed
- stored in metadata
- stored in filenames
- included in workflow output

---

# 11. Encryption key versioning

Design the backup format to support key rotation.

For example:

```text
BACKUP_ENCRYPTION_KEY_V1
BACKUP_ENCRYPTION_KEY_V2
```

Metadata should contain a non-secret key identifier:

```json
{
  "encryption_key_version": "v1"
}
```

New backups use the current key.

Old encryption keys must remain available while backups encrypted with those keys are still within their retention period.

Do not delete an old key while historical backups still require it.

---

# 12. Backup storage structure

Use UTC timestamps.

Example:

```text
database-20260921T010000Z.dump.age
```

Recommended R2 structure:

```text
backups/
  neon/
    2026/
      09/
        21/
          database-20260921T010000Z.dump.age
          database-20260921T010000Z.sha256
          database-20260921T010000Z.json
```

For Supabase:

```text
backups/
  supabase/
    2026/
      09/
        21/
          database-20260921T010000Z.dump.age
          database-20260921T010000Z.sha256
          database-20260921T010000Z.json
```

The provider must be part of the path.

---

# 13. Backup metadata

Create a metadata JSON file for every backup.

Example:

```json
{
  "provider": "neon",
  "created_at": "2026-09-21T01:00:00Z",
  "format": "postgresql-custom",
  "pg_dump_version": "...",
  "postgresql_server_version": "...",
  "encryption": "age",
  "encryption_key_version": "v1"
}
```

Do not include:

- database URLs
- passwords
- encryption keys
- access tokens
- other secrets

---

# 14. SHA-256 integrity check

Generate a SHA-256 checksum for the **encrypted** backup.

Use it to detect:

- incomplete uploads
- corruption
- accidental modification

Do not describe SHA-256 stored in the same R2 bucket as protection against an attacker who can modify both the backup and checksum.

The checksum is an integrity/corruption check, not an independent anti-tampering mechanism.

Be careful with filename binding.

If the checksum file contains:

```text
abc123...  database-20260921T010000Z.dump.age
```

the restore workflow must verify the exact filename, or calculate the downloaded file's hash directly and compare the resulting hash value.

---

# 15. R2 upload verification

Upload:

1. Encrypted backup.
2. SHA-256 checksum.
3. Metadata.

After uploading:

- Verify the backup object exists.
- Verify its object size is greater than zero.
- Verify the checksum object exists.
- Verify the metadata object exists.

Do not rely only on:

```bash
aws s3 ls
```

Use object metadata/head operations where appropriate.

Explicitly verify:

```text
ContentLength > 0
```

A successful upload command alone is not sufficient validation.

---

# 16. R2 retention

The R2 bucket already exists.

Do not create the bucket from GitHub Actions.

Configure/document lifecycle retention as a **manual Cloudflare R2 configuration step**.

Recommended retention:

```text
Daily backups:   30 days
Monthly backups: 12 months
```

A simple 30-day lifecycle rule does **not** automatically provide 12 months of monthly retention.

Therefore, implement/document a clear mechanism for retaining monthly backups for 12 months.

If this requires manual R2 lifecycle configuration, clearly identify it as manual setup.

---

# 17. Restore-test workflow

Create a separate workflow:

```text
.github/workflows/database_restore_test.yml
```

Run it automatically once per week.

Also support:

```text
workflow_dispatch
```

Recommended flow:

```text
Find latest complete backup
        ↓
Download encrypted backup
        ↓
Download checksum
        ↓
Verify checksum
        ↓
Download metadata
        ↓
Determine encryption key version
        ↓
Decrypt
        ↓
Create/use disposable restore database
        ↓
pg_restore
        ↓
Validate schema
        ↓
Validate representative data
        ↓
Cleanup restore database
        ↓
Report result
```

Never restore the automated test backup directly over production.

---

# 18. Restore target protection

Build technical safeguards against accidental production restoration.

Do not rely only on documentation.

The restore workflow must:

1. Use a dedicated restore/test database URL.
2. Never use the production database URL as the restore target.
3. Validate the target hostname/database naming convention.
4. Refuse to continue if the target is not an approved restore-test target.
5. Where practical, compare a securely derived hash of the restore URL against the production URL and refuse if they match.
6. Never print either URL.

Use a separate GitHub Environment for restore operations where appropriate.

Consider requiring a reviewer for sensitive restore operations.

Ideally, the automated restore workflow should not have production database credentials at all.

---

# 19. Disposable restore database

Prefer a disposable database for each restore test.

For Neon, investigate whether a temporary branch/database can be created for each test.

Conceptually:

```text
Neon production
       ↓
Temporary restore-test branch
       ↓
pg_restore
       ↓
Validate
       ↓
Delete branch
```

If Supabase provides an appropriate disposable/test database mechanism, isolate that provider-specific implementation.

If automatic disposable database creation is not practical, use a dedicated non-production restore database.

Never use production.

---

# 20. Restore validation

A successful `pg_restore` command alone is not sufficient.

Validate the restored database.

## Schema validation

Inspect the current Rails schema and identify several important application tables.

Verify that they exist after restoration.

Do not hard-code example table names that do not exist.

## Data validation

Check non-zero row counts for several representative core tables.

For example, if those tables actually exist:

```sql
SELECT COUNT(*) FROM users;
SELECT COUNT(*) FROM people;
```

Use actual application tables discovered from the repository.

The restore test should fail if core application data is unexpectedly empty.

## Structure validation

Where appropriate, validate:

- tables
- indexes
- foreign keys
- Rails schema/migration compatibility

---

# 21. Restore cleanup

Cleanup must occur even when restore or validation fails.

The workflow should:

- Delete disposable databases/branches.
- Attempt cleanup after failed restores.
- Report cleanup failures.
- Avoid leaving paid resources running.

Use GitHub Actions finalization logic equivalent to:

```yaml
if: always()
```

for cleanup steps.

---

# 22. Latest backup selection

The restore workflow must identify the newest **complete** backup.

Use UTC timestamps in filenames.

When selecting the backup:

- Sort explicitly by timestamp.
- Do not depend on R2 listing order.
- Require backup, checksum, and metadata objects.
- Ignore incomplete backups.
- Select the newest valid backup for the selected provider.

---

# 23. Backup freshness monitoring

Create:

```text
.github/workflows/database_backup_freshness.yml
```

Run approximately every 12 hours.

The monitor should:

1. Query R2.
2. Find the latest complete backup.
3. Determine its age.
4. Alert if it is older than approximately 36 hours.

Example:

```text
Latest backup <= 36 hours old
    → healthy

Latest backup > 36 hours old
    → alert/failure
```

This protects against the scheduled backup workflow silently stopping.

---

# 24. Failure notifications

Notify on:

- backup failure
- restore-test failure
- freshness failure

Use the existing project notification mechanism where possible.

Notifications should contain:

- workflow name
- database provider
- timestamp/run
- GitHub Actions run reference

Notifications must never contain:

- database passwords
- database URLs
- encryption keys
- access tokens

Ensure notification steps are executed appropriately after workflow failures.

---

# 25. GitHub Actions secrets

Inspect the existing secrets first.

Expected categories may include:

```text
NEON_DIRECT_DATABASE_URL
SUPABASE_DIRECT_DATABASE_URL

R2_ACCESS_KEY_ID
R2_SECRET_ACCESS_KEY
R2_ENDPOINT
R2_BUCKET

BACKUP_ENCRYPTION_KEY_V1
```

These are examples only.

Use the actual existing secret names.

Do not create duplicates unnecessarily.

Keep production database credentials separate from restore-test credentials wherever possible.

---

# 26. Provider switching

Changing:

```text
DATABASE_PROVIDER=neon
```

to:

```text
DATABASE_PROVIDER=supabase
```

should switch the database used by the backup workflow without changing:

- encryption
- R2 storage
- checksum logic
- retention
- backup naming
- generic restore validation

Provider-specific code must remain isolated.

---

# 27. Active Storage and media scope

Document explicitly:

> PostgreSQL database backups do not back up Active Storage blobs or other files stored outside PostgreSQL.

The PostgreSQL backup protects database records.

It does not automatically protect:

- uploaded images
- uploaded videos
- Active Storage blobs
- external R2/S3 assets
- other external files

If the application currently uses external video URLs, the URL records are included in PostgreSQL, but the external media itself is not.

A separate media/file backup strategy can be implemented later.

---

# 28. Threat model

Document what each protection provides.

## Native Neon/Supabase backups

Provide provider-level recovery capabilities such as point-in-time recovery where supported.

## Independent R2 backups

Provide an independent recovery copy useful for:

- provider outage
- provider account problems
- provider lockout
- provider migration
- independent disaster recovery

## Encryption

Protects backup contents if an encrypted object is obtained without the encryption key.

## SHA-256

Detects corruption or unintended modification.

It should not be described as strong tamper protection when both backup and checksum are stored in the same storage account.

## Restore testing

Provides evidence that the backup can actually be recovered.

---

# 29. Historical restore testing

The weekly automated restore test should normally use the newest backup.

In addition, perform a periodic historical restore test.

At least every few months:

1. Select an older retained backup.
2. Restore it into a disposable environment.
3. Validate schema.
4. Validate representative data.
5. Verify application connectivity.
6. Record the result.

This validates the historical retention set, not only the newest backup.

---

# 30. Operational documentation

Create or update:

```text
docs/database-backups.md
```

Document:

- backup architecture
- provider selection
- required secrets
- backup schedule
- R2 storage structure
- retention
- encryption
- key rotation
- restore procedure
- restore-test procedure
- freshness monitoring
- failure notifications
- disaster recovery
- Active Storage/media limitations
- manual R2 configuration

Include an emergency recovery checklist:

```text
1. Identify the required backup.
2. Verify its checksum.
3. Identify the encryption key version.
4. Decrypt the backup.
5. Create a safe restore target.
6. Restore the database.
7. Validate schema and representative data.
8. Validate application connectivity.
9. Only then consider switching application traffic.
10. Record the recovery details.
```

---

# 31. Files to create/update

At minimum:

```text
.github/workflows/database_backup.yml
.github/workflows/database_restore_test.yml
.github/workflows/database_backup_freshness.yml
docs/database-backups.md
```

If useful, extract shell logic into small version-controlled scripts:

```text
script/database_backup
script/database_restore_test
script/database_backup_freshness
```

Prefer small testable scripts over very large YAML shell blocks.

---

# 32. Testing requirements

Before declaring the implementation complete, test:

## Backup

- Manual backup execution.
- Scheduled workflow configuration.
- Neon backup.
- Supabase backup, if configured.
- Direct database connection.
- PostgreSQL client/server compatibility.
- Encryption.
- Checksum generation.
- R2 upload.
- R2 object-size verification.
- Metadata generation.
- Secret redaction.

## Failure cases

Test controlled failures for:

- invalid database URL
- unavailable database
- `pg_dump` failure
- PostgreSQL version mismatch
- encryption failure
- R2 upload failure
- corrupted backup
- corrupted checksum
- missing metadata
- stale backup

## Restore

Test:

- latest backup selection
- checksum verification
- decryption
- restore
- schema validation
- representative data validation
- production-target protection
- cleanup

## Freshness

Verify:

```text
backup age <= 36h
```

is healthy and:

```text
backup age > 36h
```

causes an alert/failure.

---

# 33. Security requirements

The implementation must:

- Never log database credentials.
- Never log encryption keys.
- Never commit secrets.
- Never upload plaintext database dumps.
- Never restore automated tests into production.
- Never use `set -x`.
- Delete temporary plaintext dumps.
- Use authenticated encryption.
- Verify checksums before restore.
- Maintain encryption key versions.
- Separate restore-test credentials from production credentials where possible.
- Use GitHub Environment protection where appropriate.
- Fail closed when the restore target is unsafe.

---

# 34. Deliverables from the coding agent

After implementation, report:

1. Files created.
2. Files modified.
3. GitHub Actions workflows created.
4. Existing secrets used.
5. Any new secrets required.
6. Provider-selection mechanism.
7. PostgreSQL client version used.
8. Encryption mechanism.
9. Backup naming/storage structure.
10. Retention implementation/documentation.
11. Restore-test implementation.
12. Production restore safeguards.
13. Validation checks.
14. Freshness monitoring.
15. Failure notification mechanism.
16. Tests executed and their results.
17. Neon-specific limitations.
18. Supabase-specific limitations.
19. Manual Cloudflare R2 configuration still required.
20. Manual GitHub configuration still required.
21. Remaining risks or follow-up work.

Do not claim that the system is production-ready if required manual configuration or tests remain incomplete.

---

# 35. Final implementation principle

Prioritize operational reliability over unnecessary complexity.

The target design is:

```text
simple provider selection
        +
direct PostgreSQL connection
        +
pinned pg_dump
        +
custom-format backup
        +
authenticated encryption
        +
SHA-256 verification
        +
Cloudflare R2
        +
daily/long-term retention
        +
weekly restore testing
        +
production restore safeguards
        +
freshness monitoring
```

The objective is not merely to create backup files.

The objective is to maintain backups that can be **verified, recovered, and trusted during a real production incident**.
