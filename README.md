# README

This README would normally document whatever steps are necessary to get the
application up and running.

Things you may want to cover:

* Ruby version

* System dependencies

* Configuration

* Database creation

* Database initialization

* How to run the test suite

* Services (job queues, cache servers, search engines, etc.)

* Deployment instructions

* ...
# beachvolleyballproject_api

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

