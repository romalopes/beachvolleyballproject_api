# Local development, Vercel and Render configuration

Checked against the workspace source on 8 October 2026. This documents configuration; it does not confirm the settings of any deployed service. Values in angle brackets are placeholders. Never put backend secrets in `VITE_*` variables: those become public browser JavaScript.

## Is this already documented?

Partly, but there was no complete setup guide:

- [API README](../README.md): mostly Rails boilerplate, plus private test-access and video documentation.
- API [`.env.example`](../.env.example): email configuration only; missing database, storage, authentication flags and deployment settings.
- Frontend `README.md`: mostly Vite boilerplate. Its `.env.example` documents `VITE_API_BASE_URL`.
- [Domain setup](beachvolleyballproject_domain_setup.md): DNS and provider architecture, with illustrative variables. Its `EMAIL_PROVIDER` and backend `API_BASE_URL` examples are **not read by the current application**. Use `MAIL_TRANSPORT`, `FRONTEND_URL` and `APP_HOST` below.
- [Email transport documentation](IDENTITY_226_mail_transport/README.md): provider selection and verification.
- [Database backup and restore](DATABASE_BACKUP_AND_RESTORE.md): operational backup procedures.

This guide follows executable configuration rather than stale comments. Development currently selects **Cloudflare R2**, production selects **Supabase S3**, and Puma unconditionally binds to local HTTPS. Environment variables alone do not change these choices.

## 1. Project layout and prerequisites

The workspace contains two separate Git repositories:

```text
beachvolleyballproject/      React / TypeScript / Vite frontend
beachvolleyballproject_api/  Rails API (this repository)
```

Install Ruby **3.4.2** (`.ruby-version`), Bundler **2.7.2** (`Gemfile.lock`), Node.js **24.x** with npm, PostgreSQL with a running server, PostgreSQL client/development libraries for the `pg` gem, OpenSSL, and libvips for image processing. Rails is installed by Bundler. The Node choice satisfies the frontend lockfile's modern engine requirements.

On macOS, PostgreSQL/libvips can be installed through Homebrew; ensure PostgreSQL is started and `pg_config` is on `PATH`. Create a PostgreSQL login and a development database owned by that login, or give the login database-creation permission for `db:create`. Keep production and development databases separate.

## 2. Run locally

### API environment

From the API repository, copy `.env.example` to `.env.development` **only if the destination does not already exist**, then merge the following settings into it:

```dotenv
DATABASE_URL=postgresql://<local-user>:<url-encoded-password>@localhost:5432/beachvolleyballproject_development
FRONTEND_URL=http://localhost:5174
APP_HOST=localhost
MAIL_TRANSPORT=file
MAIL_FROM="BVB Project <no-reply@example.com>"
MAIL_REPLY_TO=support@example.com
TEST_ACCESS_PASSWORD=
TEST_ACCESS_TOKEN_EXPIRATION=7.days
REQUIRE_EMAIL_VERIFICATION=false
EMAIL_VERIFICATION_EXPIRATION_HOURS=24
EMAIL_VERIFICATION_AUTO_SEND_ON_SIGNUP=true
CLAIM_INVITATION_EMAIL_ENABLED=false
WEB_CONCURRENCY=0
RAILS_MAX_THREADS=5
```

`dotenv-rails` loads development files; existing exported shell variables and higher-priority `.env.development.local`/`.env.local` values can override `.env.development`. Check for conflicts with existing `.env` files. Restart Rails after changing configuration. Production does not load these files because dotenv is a development-only dependency.

### Choose development storage before initializing data

The active line in `config/environments/development.rb` is:

```ruby
config.active_storage.service = :cloudflare_r2
```

For fully local storage, **replace that active line** with `config.active_storage.service = :local`. This is a manual configuration change, not an existing environment switch. Uploaded files then live in `storage/`. Alternatively, keep R2 and set every required R2 variable in section 5. Seeds attach a sample logo, so storage must work before running seeds or `db:prepare` on a new database.

### Install, initialize and start

Run inside `beachvolleyballproject_api/`:

```bash
gem install bundler -v 2.7.2
bundle install
bin/rails db:create db:migrate
# Optional sample skills, drills and organisations:
bin/rails db:seed
```

The seed file does not create a login account; register through the UI.

Puma requires `config/ssl/localhost.key` and `config/ssl/localhost.crt`. If missing, generate local-only certificates (do not overwrite existing ones unnecessarily):

```bash
mkdir -p config/ssl
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout config/ssl/localhost.key \
  -out config/ssl/localhost.crt -days 365 -subj '/CN=localhost'
bin/rails server
```

Keep the generated private key out of commits. The API listens on **https://127.0.0.1:3001**. Vite proxies `/api` and `/rails` to this address and accepts its self-signed certificate.

In another terminal, inside `beachvolleyballproject/`, create or edit `.env.local`:

```dotenv
VITE_API_BASE_URL=/api/v1
```

Then run:

```bash
npm ci
npm run dev
```

Open **http://localhost:5174**. Use that origin for browsing; pointing the browser directly at the self-signed API bypasses the Vite proxy. If port 5174 is occupied, free it so the frontend URL and mail links stay aligned.

Check connectivity:

```bash
curl -k https://127.0.0.1:3001/api/v1/health
curl http://localhost:5174/api/v1/health
```

`-k` is only for the local self-signed certificate. Local file emails appear in API `tmp/mails/`. Enable the email flags below to exercise verification/invitation flows. Development uses the default in-process Active Job adapter; production needs the worker described below.

## 3. Vercel frontend

Import the frontend repository. If importing a combined repository instead, set Root Directory to `beachvolleyballproject`; for the standalone frontend repository, use its root.

| Setting | Value |
|---|---|
| Framework preset | Vite |
| Node.js | 24.x |
| Install command | `npm ci` |
| Build command | `npm run build` |
| Output directory | `dist` |

Set this in Project Settings → Environment Variables:

| Variable | Local | Vercel Production | Vercel Preview |
|---|---|---|---|
| `VITE_API_BASE_URL` | `/api/v1` | `https://<production-api>.onrender.com/api/v1` or custom API domain | URL of the staging API, including `/api/v1` |

This is the only application-defined frontend environment variable currently read by the source. Vite's `import.meta.env.DEV` is automatic. Do not set database, mail, Rails or storage secrets on the frontend. Redeploy after changing the API URL: Vite embeds it during the build. The local dev proxy is not deployed to Vercel. See [Vercel's Vite guide](https://vercel.com/docs/frameworks/frontend/vite).

### Required routing for organisation logos

The API returns relative `/rails/active_storage/...` logo URLs, and React renders them unchanged. The existing `vercel.json` only rewrites everything to `index.html`; that is insufficient for these images. Before deployment, update it to proxy `/rails` **before** the SPA fallback, replacing the example host:

```json
{
  "rewrites": [
    {
      "source": "/rails/:path*",
      "destination": "https://<production-api>.onrender.com/rails/:path*"
    },
    { "source": "/(.*)", "destination": "/index.html" }
  ]
}
```

This is a required manual configuration change, not applied by this guide. The destination is a literal URL, independent of `VITE_API_BASE_URL`. For previews backed by a different API, also provide matching routing; otherwise their logos would be requested from production.

## 4. Render API and worker

Create a **Ruby Web Service** from the API repository. Use the repository root, or `beachvolleyballproject_api` for a combined repository. Ruby is pinned by `.ruby-version`.

| Setting | Value |
|---|---|
| Build command | `bash bin/render-build.sh` |
| Start command | `bundle exec puma -C /dev/null -b tcp://0.0.0.0:$PORT -e production -w ${WEB_CONCURRENCY:-0} -t 0:${RAILS_MAX_THREADS:-5} config.ru` |
| Health check path | `/api/v1/health` |

The explicit start command skips `config/puma.rb`, whose unconditional local SSL bind would otherwise require local certificates and fail to expose the correct Render interface. Render terminates public HTTPS; the process binds HTTP on `0.0.0.0:$PORT`. This command also explicitly applies worker/thread settings because it skips the Puma configuration. See [Render's port-binding requirements](https://render.com/docs/web-services#port-binding).

The build script installs gems, precompiles assets and runs primary/cache/queue/cable migrations. **It changes the configured database during the build.** Provision the database first and set `DATABASE_URL` before building. All four connections currently share that URL. The repository includes migrations creating the Solid Cache, Queue and Cable tables. Check `bin/rails db:migrate:status` after deployment if tables are missing; do not load schemas over an existing database. Consult the backup guide before changes to an existing deployment.

Create a **Background Worker** from the same API revision, with the same production database, Rails key, email and storage configuration:

- Build command: `bundle install` (web-service deployment performs migrations first).
- Start command: `bundle exec ruby bin/jobs`.
- Set `JOB_CONCURRENCY=1` initially.

Production uses Solid Queue. Without its worker, queued password-reset and claim-decision emails will not be processed. No Redis service is required by the current configuration. See [Render's Rails deployment guide](https://render.com/docs/deploy-rails-8).

### Render baseline environment

Enter values in Render's Environment settings; do not include dotenv quote characters in dashboard values.

```dotenv
RAILS_ENV=production
DATABASE_URL=<PostgreSQL connection URL supplied by database provider>
RAILS_MASTER_KEY=<key matching the deployed encrypted Rails credentials>
SECRET_KEY_BASE=<stable random secret generated with bin/rails secret>
WEB_CONCURRENCY=0
RAILS_MAX_THREADS=5
JOB_CONCURRENCY=1
FRONTEND_URL=https://<frontend>.vercel.app
APP_HOST=<api>.onrender.com
MAIL_TRANSPORT=resend
RESEND_API_KEY=<Resend API key>
MAIL_FROM=BVB Project <no-reply@your-verified-domain.example>
MAIL_REPLY_TO=support@your-domain.example
REQUIRE_EMAIL_VERIFICATION=true
EMAIL_VERIFICATION_AUTO_SEND_ON_SIGNUP=true
EMAIL_VERIFICATION_EXPIRATION_HOURS=24
CLAIM_INVITATION_EMAIL_ENABLED=true
SUPABASE_S3_ACCESS_KEY_ID=<S3 access key ID>
SUPABASE_S3_SECRET_ACCESS_KEY=<S3 secret access key>
SUPABASE_S3_REGION=<bucket region>
SUPABASE_S3_BUCKET_NAME=<bucket name>
SUPABASE_PROJECT_REF=<project reference>
```

Use the database provider's SSL parameters where required. For Render Postgres, use its internal URL when accessible from the service. Verification/invitation flags above enable those features deliberately; their code defaults are false. Verify actual mail delivery before enabling verification for users. Brevo can replace Resend using the variables below.

## 5. Backend environment reference

All variables here belong on the API/worker, never in the Vercel browser bundle. “Default” describes current source behavior, not necessarily the recommended production value.

### Core and runtime

| Variable | Local configuration | Render configuration / meaning |
|---|---|---|
| `DATABASE_URL` | Required development PostgreSQL URL | Required hosted PostgreSQL URL; contains credentials. Also used for primary/cache/queue/cable. |
| `RAILS_ENV` | Unset or `development` | `production` on web service and worker. |
| `RAILS_MASTER_KEY` | Existing `config/master.key`, or matching environment key if encrypted credentials are used | Secret matching the deployed credentials; do not generate an unrelated key. |
| `SECRET_KEY_BASE` | Rails can generate a development secret | Stable secret from `bin/rails secret`, or configured encrypted credentials. Changing it invalidates signed credentials/tokens. |
| `FRONTEND_URL` | `http://localhost:5174` | Public frontend origin, including `https://`, without `/api/v1`; used for email links. Production fallback is `https://beachvolleyballproject.vercel.app`. |
| `APP_HOST` | Development mailer currently hardcodes localhost:3001 | API hostname only, no protocol/path; production mailer URL host, default `example.com`. |
| `APP_VERSION` | Optional; default `0.0.21` | API health/version value; keep aligned with frontend `src/constants/versions.ts`. |
| `WEB_CONCURRENCY` | Default `0` | Start at `0` for a single process; increase according to memory/CPU. Repository Puma default is `2` in production, but the documented Render command defaults to `0`. |
| `RAILS_MAX_THREADS` | Default database pool limit `5` | `5` initially; also controls threads in the documented Render command. Repository Puma does not directly read it for threads. Account for worker and multiple-database connections when sizing PostgreSQL. |
| `JOB_CONCURRENCY` | Usually unnecessary locally | Worker process count; default `1`; each configured queue worker has 3 threads. |
| `RAILS_LOG_LEVEL` | Development uses Rails default | Default `info`. Production currently overrides its stdout logger with `log/production.log`; setting this variable does not restore stdout logging. |
| `PORT` | Local Puma hardcodes 3001 | Render-provided; consumed by the documented start command. |
| `PIDFILE` | Optional; Puma default `tmp/pids/server.pid` | Not consumed when using the documented `-C /dev/null` command. |
| `SECRET_KEY_BASE_DUMMY` | Not needed | Build script temporarily sets `1` for asset compilation; do not set as a runtime substitute for the real secret. |
| `OBJC_DISABLE_INITIALIZE_FORK_SAFETY` | Puma sets `YES` on macOS | Not needed on Render Linux. |
| `CI` | Only relevant to tests | Presence enables eager loading in test; not a production setting. |
| `BUNDLE_GEMFILE` | Automatically set by Rails boot | Normally leave unset; internal Bundler file selection. |

`RAILS_MASTER_KEY` decrypts credentials; it is not interchangeable with `SECRET_KEY_BASE`.

### Access and email feature flags

| Variable | Default | Configuration |
|---|---|---|
| `TEST_ACCESS_PASSWORD` | Blank: private testing gate disabled | Leave blank locally; set a backend-only secret on Render to enable the gate. Separate from user passwords. |
| `TEST_ACCESS_TOKEN_EXPIRATION` | `7.days` | Positive duration, e.g. `12.hours`, `3600` seconds or `P7D`. Password rotation does not immediately invalidate already-issued tokens. |
| `REQUIRE_EMAIL_VERIFICATION` | `false` | `true` requires new users to verify their email. |
| `EMAIL_VERIFICATION_EXPIRATION_HOURS` | `24` | Positive numeric lifetime in hours. |
| `EMAIL_VERIFICATION_AUTO_SEND_ON_SIGNUP` | `true` | `false` requires users to request verification delivery manually; relevant when verification is enabled. |
| `CLAIM_INVITATION_EMAIL_ENABLED` | `false` | `true` sends claim-invitation emails; otherwise share generated links manually. |

### Email transport

| Variable | Local | Render |
|---|---|---|
| `MAIL_TRANSPORT` | `file` writes to `tmp/mails` | Explicit `resend`, `brevo` or `smtp`; `auto`/unset selects Brevo → Resend → SMTP → file according to configured credentials. |
| `MAIL_FROM` | Example sender for file delivery | Sender address/name authenticated with the provider. Unset uses the legacy sender in `lib/mail_sender.rb`. |
| `MAIL_REPLY_TO` | Example reply address | Real receiving mailbox; unset uses the legacy reply address. |
| `BREVO_API_KEY` | Only for Brevo testing | Secret required for `brevo`; omit for other providers. |
| `RESEND_API_KEY` | Only for Resend testing | Secret required for `resend`; omit for other providers. |
| `SMTP_ADDRESS` | Optional SMTP hostname | Required for `smtp`; omit for HTTP providers. |
| `SMTP_PORT` | Default `587` | Provider port. Ensure outbound SMTP is supported by the service. |
| `SMTP_DOMAIN` | Default `localhost` | Provider-required SMTP HELO domain. |
| `SMTP_USERNAME` | Optional | Provider login, if required. |
| `SMTP_PASSWORD` | Optional secret | Provider password/API credential, if required. |
| `SMTP_AUTHENTICATION` | Default `plain` | Provider-supported authentication method. |
| `SMTP_ENABLE_STARTTLS` | Default `true` | Only literal `true` enables automatic STARTTLS. |

Missing credentials for an explicitly chosen transport cause fallback, not necessarily a boot failure. Successful application boot does not prove outbound delivery; check the effective transport and delivery. File delivery on Render is not external email and is not durable storage.

### Storage

Storage selection is hardcoded in environment Ruby files; there is no `ACTIVE_STORAGE_SERVICE` environment switch. Development is R2, production is Supabase, tests use temporary disk. Set credentials for the selected service only.

| Variable | Required when | Value |
|---|---|---|
| `CLOUD_FLARE_R2_ACCESS_KEY_ID` | R2 | Bucket-authorized S3 access key ID. |
| `CLOUD_FLARE_R2_ACCESS_KEY` | R2 | Secret access key; spelling is intentional (no `_SECRET_`). |
| `CLOUD_FLARE_R2_BUCKET` | R2 | Existing bucket name. |
| `CLOUD_FLARE_R2_ENDPOINT` | R2, unless using `REF` | Full S3 API endpoint, e.g. `https://<account-id>.r2.cloudflarestorage.com`; not a public asset URL. |
| `CLOUD_FLARE_R2_REF` | R2 when endpoint omitted | Account ID used to construct the endpoint. Omit `ENDPOINT` entirely when using this fallback; an empty string overrides it. Region is hardcoded `auto`. |
| `SUPABASE_S3_ACCESS_KEY_ID` | Supabase / current production | S3 access key ID, not an anon key. |
| `SUPABASE_S3_SECRET_ACCESS_KEY` | Supabase / current production | S3 secret access key. |
| `SUPABASE_S3_REGION` | Supabase / current production | Region reported by the project's S3 connection settings. |
| `SUPABASE_S3_BUCKET_NAME` | Supabase / current production | Existing bucket name. |
| `SUPABASE_PROJECT_REF` | Supabase / current production | Project reference; endpoint becomes `https://<ref>.supabase.co/storage/v1/s3`. |
| `NEON_S3_ACCESS_KEY_ID` | Inactive `neon` storage entry only | S3 access key ID. |
| `NEON_S3_SECRET_ACCESS_KEY` | Inactive `neon` entry only | S3 secret. |
| `NEON_S3_REGION` | Inactive `neon` entry only | Region. |
| `NEON_S3_BUCKET_NAME` | Inactive `neon` entry only | Bucket. |
| `NEON_PROJECT_ID` | Inactive `neon` entry only | Project ID. This entry still contains literal `<region>` in its endpoint and is not ready to use without a code change and provider verification. |

Using Neon for PostgreSQL does not require any `NEON_S3_*` variables. To use R2 on Render, change the production storage service to `:cloudflare_r2` and provide its credentials instead of Supabase's. Changing providers does not migrate existing uploaded objects.

## 6. Verification and common configuration problems

1. Open the API `/api/v1/health` directly over HTTPS, then open the Vercel frontend. Confirm browser API requests reach the intended environment.
2. Register/sign in, pass the private test gate if enabled, and test password reset and verification with an address you control.
3. Confirm the production worker processes queued mail; inspect API logs, `tmp/mails` locally, and provider delivery logs remotely.
4. Upload and view an organisation logo. Confirm `/rails/active_storage/...` returns an image through Vercel, not `index.html`.
5. Reload a nested frontend route to verify the SPA fallback.

Troubleshooting:

- **Local proxy 502 / connection refused:** Rails must be running on HTTPS port 3001 with the certificate files. The frontend runs on HTTP port 5174.
- **API request returns frontend HTML:** missing/incorrect Vercel `VITE_API_BASE_URL`, or missing `/api/v1`. Redeploy after correcting it.
- **Upload/signature errors:** check the actually selected storage service and its S3 credentials; development currently does not default to disk.
- **Render cannot detect a port:** use the explicit start command above; plain `rails server` loads the local-only SSL bind.
- **Reset emails never arrive:** check both transport selection and Solid Queue worker, plus frontend URL and sender authentication.
- **CORS settings appear ineffective:** current `config/initializers/cors.rb` allows `*`; `FRONTEND_URL` does not control CORS. Restrict origins by editing that initializer if needed.
- **No application logs in Render's log stream:** production currently writes to `log/production.log`. Edit the final logger assignment to use stdout for platform log capture; `RAILS_LOG_LEVEL` alone cannot fix this.

Source checkpoints: `config/database.yml`, `config/puma.rb`, `config/storage.yml`, `config/environments/*.rb`, `config/initializers/`, `config/queue.yml`, `lib/mail_transport.rb`, `lib/mail_sender.rb`, `bin/render-build.sh`; frontend `src/api.ts`, `vite.config.ts`, `vercel.json`, `package.json` and `package-lock.json`.
