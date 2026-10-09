# Beach Volleyball API

For architecture overview and documentation index, see [Architecture overview and documentation index](docs/architecture/architecture.md).

Rails backend for the Beach Volleyball Project’s React frontend.

## Setup and operations

| Guide | Use it for |
|---|---|
| [Local, Vercel and Render setup](docs/LOCAL_VERCEL_RENDER_SETUP.md) | Prerequisites, startup commands, environment variables, storage, email and deployment configuration. |
| [Database backup and restore](docs/DATABASE_BACKUP_AND_RESTORE.md) | Initial backup setup, GitHub Actions, R2 downloads, decryption, restore validation and production recovery. |
| [Domains, DNS and email setup](docs/beachvolleyballproject_domain_setup.md) | Custom-domain rollout and provider DNS settings; illustrative variables must be checked against the setup guide. |
| [Email transport overview](docs/IDENTITY_226_mail_transport/README.md) | Brevo, Resend, SMTP and local file delivery. |
| [Email environment and sender configuration](docs/IDENTITY_226_mail_transport/03_ENVIRONMENT_SENDER_AND_ROLLOUT.md) | Provider credentials, sender identity and rollout. |
| [Email operations and verification](docs/IDENTITY_226_mail_transport/04_OPERATIONS_AND_VERIFICATION.md) | Transport checks and delivery troubleshooting. |
| [Send a test email](docs/IDENTITY_226_mail_transport/05_SEND_TEST_EMAIL.md) | Exercise outbound delivery. |

## Architecture and implementation references

These documents include design plans, audits and phase reports; consult their status
and the current code before treating planned behavior as implemented.

| Reference | Topic |
|---|---|
| [Person identity model](docs/IDENTITY_228_ACCOUNT_CENTRIC/PERSON_IDENTITY_MODEL.md) | Accounts, people and profiles. |
| [Account identity phase status](docs/IDENTITY_228_ACCOUNT_CENTRIC/IDENTITY_228_PHASE_STATUS.md) | Account-centric implementation and links to its phases. |
| [Profile phase status](docs/IDENTITY_255_PROFILES/IDENTITY_225_PHASE_STATUS.md) | Profile ownership, claims, lifecycle and rollout work. |
| [Organisation tree and membership plan](docs/IDENTITY_231_REFACTOR_ORGANISATIONS/beachvolleyballproject-organisation-tree-membership-plan.md) | Organisation hierarchy and memberships. |
| [Assessment definitions](docs/IDENTITY_28_ASSESSMENT/ASSESSMENT_DEFINITIONS_PLAN.md) | Assessment structure. |
| [Assessment sessions](docs/IDENTITY_28_ASSESSMENT/ASSESSMENT_SESSIONS_PLAN.md) | Assessment session design. |
| [Assessment integration](docs/IDENTITY_28_ASSESSMENT/ASSESSMENT_INTEGRATION_PLAN.md) | Integration work across assessment features. |
| [Tournament calendar plan](docs/IDENTITY_76_TOURNAMENT/bvb-tournament-calendar-issue-76-plan.md) | Tournament and calendar design. |
| [README documentation plan](<docs/Beach Volleyball Project — README.md Documentation Plan.md>) | Broader documentation roadmap. |

## Private test-access gate

The application is in a private testing phase. While the gate is enabled, the
browser must first exchange a password for a signed, expiring token and send
that token on every API request (header `X-Test-Access-Token`).

* **Password**: server-side only, from the `TEST_ACCESS_PASSWORD` environment
  variable (Render env var in production). It is **never** in the React source
  and **never** committed. Leave it blank locally to disable the gate.
* **Token**: signed with Rails' `message_verifier` (`TestAccessToken`), expires
  after `TEST_ACCESS_TOKEN_EXPIRATION` (default 7 days). It is not a User
  credential and does not touch the existing User/Session authentication.
* **Endpoints** (open even when the gate is on):
  * `POST /api/v1/test_access` `{ "password": "…" }` →
    `{ authenticated: true, token, expires_at }` or 401
    `{ authenticated: false, error: "Invalid password" }` (rate-limited).
  * `GET /api/v1/test_access` — verifies the header token.
  * `GET /api/v1/health` — stays public for uptime probes.
* **Rotating the password**: change `TEST_ACCESS_PASSWORD` on Render and
  restart. Old tokens keep working until they expire. Generating a new token does not
  revoke existing tokens. Changing the `PURPOSE` constant invalidates all
  test-access tokens and requires a deployment.
* **Removing the feature later**: delete `app/services/test_access_token.rb`,
  `app/controllers/concerns/test_access.rb`,
  `app/controllers/api/v1/test_access_controller.rb`, the two `test_access`
  routes, the `include TestAccess` line in
  `app/controllers/api/v1/application_controller.rb`, and the matching React
  gate (`src/auth/TestAccessContext.tsx`, `src/pages/TestAccess.tsx`). The
  User/Session authentication system is unaffected throughout.

Local setup:

```bash
cp .env.example .env.development
# edit .env.development: TEST_ACCESS_PASSWORD=<choose a secret>
```

Use a **different** password than the Wine Words API in production.

# Videos & VideoReferences

> **A Video represents the actual media resource. A VideoReference represents
> the contextual use of that video by a Drill or Skill, including timestamps
> and description.**

The legacy flat `media_assets` table (a URL attached to a single drill/skill)
was merged into this domain by the `MergeMediaAssetsIntoVideos` migration and
dropped. `training_session_media_assets` was dropped too — a future
TrainingSession reference needs no new table thanks to polymorphism.

## Models

* `Video` — `provider`, `provider_video_id`, `source_url`, `storage_key`
  (NULL for external videos; reserved for future S3 uploads), `title`,
  `description`, `duration_seconds`, `thumbnail_url`, `created_by`.
  Provider/id/normalized URL/thumbnail are detected from `source_url` on
  validation; an unusable URL is rejected. `(provider, provider_video_id)` is
  unique (partial index; future S3 rows with NULL id are exempt), so the same
  clip added to many entities is stored once
  (`Video.find_or_create_from_url!`).
* `VideoReference` — polymorphic `referenced` (Drill, Skill, and later
  TrainingSession/Tournament/… without new tables), `start_seconds` /
  `end_seconds` (integer seconds; end optional; `end > start` enforced by
  validations and DB check constraints; a duration boundary is enforced only
  when the video's duration is known), per-use `title`/`description` and
  `position`. Deleting a reference never deletes the shared Video.

## Provider abstraction

`app/models/video_providers/` — one class per provider, registered in
`video_providers.rb`. Capabilities are declared server-side and exposed as
normalized fields (`can_embed`, `embed_url`, `external_url`,
`provider_label`); embed URLs are built only from allowlisted hosts plus the
extracted id, so user input never becomes an iframe source.

| Provider | can_embed | start | end | thumbnail |
|---|---|---|---|---|
| youtube | yes (`youtube-nocookie`) | yes (`start=`) | yes (`end=`) | i.ytimg.com |
| vimeo | yes (`player.vimeo.com`) | yes (`#t=`) | no | none |
| instagram | no | no | no | none |
| tiktok | no | no | no | none |
| external | no | no | no | none |
| s3 (future) | reserved | — | — | generated later |

**Adding a provider:** create `video_providers/<name>.rb` extending
`VideoProviders::Base` (match?/extract_id/normalized_url/embed_url/thumbnail
plus capabilities), add the class to the `registry` array, and add the
provider name to the inclusion list on `Video`. The API and the React app
need no change.

## API

* `GET /api/v1/videos` — public video library with `reference_count`.
* `POST/PATCH/DELETE /api/v1/drills/:drill_id/video_references(/:id)`,
  `/api/v1/skills/:skill_id/video_references(/:id)` and
  `/api/v1/training_sessions/:training_session_id/video_references(/:id)` —
  the reference target comes from the URL. Create accepts
  `video: { source_url, … }` (reusing an existing matching Video) or
  `video_id`. Update touches only the reference.
* Drill/Skill/TrainingSession `show` embed `video_references` (with `video`) —
  the frontend renders the embed or the fallback from `can_embed`/`embed_url`.

Authorization: create requires coach/admin (`require_content_creator!`);
update/destroy require the video's creator or an admin
(`authorize_content_owner!`).

