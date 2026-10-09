# Model catalogue

[Architecture index](architecture.md) · [Relationship diagrams](model_relationships.md)

This inventory covers every top-level class in `app/models` as of 9 October 2026.
Each entry links to its implementation. Association names are reproduced from Ruby:
`belongs_to` names such as `created_by` may point to a class with a different name.
Read the linked declaration for foreign keys, optionality, dependencies and scopes.
Through-associations are navigation paths, not additional tables. State constants
list valid values; they do not authorize every possible transition.

## Account

Application identity and private contact/profile ownership boundary. [Source](../../app/models/account.rb).

| Association | Names |
|---|---|
| `belongs_to` | `user` |
| `has_one` | `account_address`, `contact_detail` |
| `has_many` | `player_profiles`, `coach_profiles`, `organisation_memberships`, `profile_organisation_memberships`, `group_memberships`, `organisations`, `groups` |

## AccountAddress

Optional postal address for an account. [Source](../../app/models/account_address.rb).

| Association | Names |
|---|---|
| `belongs_to` | `account` |

## AdminActivity

Administrative entity/action audit record. [Source](../../app/models/admin_activity.rb).

| Association | Names |
|---|---|
| `belongs_to` | `user` |

## AppSetting

Stored application configuration keyed by name. [Source](../../app/models/app_setting.rb).

## ApplicationRecord

Abstract Active Record base; not a domain table. [Source](../../app/models/application_record.rb).

## Assessment

Coach rating of a player, standalone or definition/session-based. [Source](../../app/models/assessment.rb).

| Association | Names |
|---|---|
| `belongs_to` | `player_profile`, `coach_profile`, `created_by`, `category`, `assessment_definition`, `training_session`, `assessment_session` |
| `has_many` | `assessment_category_scores` |

Statuses: `draft`, `active`, `withdrawn`.

## AssessmentCategory

Definition category, weight/order and criteria. [Source](../../app/models/assessment_category.rb).

| Association | Names |
|---|---|
| `belongs_to` | `assessment_definition`, `category`, `category_custom` |
| `has_many` | `assessment_category_scores`, `criteria` |

## AssessmentCategoryScore

Category/criterion rating inside an assessment. [Source](../../app/models/assessment_category_score.rb).

| Association | Names |
|---|---|
| `belongs_to` | `assessment`, `assessment_category`, `criterion` |

## AssessmentDefinition

Reusable weighted assessment configuration. [Source](../../app/models/assessment_definition.rb).

| Association | Names |
|---|---|
| `belongs_to` | `created_by` |
| `has_many` | `assessment_categories`, `assessments`, `assessment_sessions`, `ranking_consolidations` |

Statuses: `draft`, `active`, `archived`.

## AssessmentSession

A scored roster using a definition and coach. [Source](../../app/models/assessment_session.rb).

| Association | Names |
|---|---|
| `belongs_to` | `assessment_definition`, `coach_profile`, `created_by`, `group` |
| `has_many` | `participants`, `assessments`, `consolidation_sessions`, `ranking_consolidations` |

Statuses: `draft`, `published`, `withdrawn`.

## AssessmentSessionParticipant

Player inclusion in an assessment session. [Source](../../app/models/assessment_session_participant.rb).

| Association | Names |
|---|---|
| `belongs_to` | `assessment_session`, `player_profile` |

## Category

Shared skill category, also usable as an assessment rubric source. [Source](../../app/models/category.rb).

| Association | Names |
|---|---|
| `has_many` | `skills`, `assessment_categories` |

## CategoryCustom

Authored rubric outside the shared category catalogue. [Source](../../app/models/category_custom.rb).

| Association | Names |
|---|---|
| `belongs_to` | `created_by` |
| `has_many` | `assessment_categories` |

Visibilities: `shared`, `private`.

## ClaimInvitation

Expiring invitation to link a profile, with token digest and usage audit. [Source](../../app/models/claim_invitation.rb).

| Association | Names |
|---|---|
| `belongs_to` | `claimable`, `invited_by`, `used_by` |

Statuses: `active`, `used`, `revoked`, `expired`, `declined`.

## CoachProfile

Independent volleyball coach identity and history anchor. [Source](../../app/models/coach_profile.rb).

| Association | Names |
|---|---|
| `belongs_to` | `created_by`, `created_by_account`, `account`, `merged_into_profile`, `merged_by_account` |
| `has_many` | `merged_profiles`, `claim_invitations`, `organisation_memberships`, `player_claims`, `assessment_sessions`, `assessments`, `player_coaches`, `players` |

Statuses: `active`, `archived`.

Visibilities: `shared`, `private`.

## ContactDetail

Required private account contact/name record. [Source](../../app/models/contact_detail.rb).

| Association | Names |
|---|---|
| `belongs_to` | `account` |

## Criterion

Scoring criterion inside an assessment category. [Source](../../app/models/criterion.rb).

| Association | Names |
|---|---|
| `belongs_to` | `assessment_category` |
| `has_many` | `assessment_category_scores` |

## Current

Request-local session/user context; not a database table. [Source](../../app/models/current.rb).

## Drill

Reusable training exercise and structured drill definition. [Source](../../app/models/drill.rb).

| Association | Names |
|---|---|
| `belongs_to` | `created_by` |
| `has_many` | `drill_skills`, `skills`, `video_references`, `videos`, `training_session_drills`, `training_sessions` |

## DrillSkill

Many-to-many exercise/skill join. [Source](../../app/models/drill_skill.rb).

| Association | Names |
|---|---|
| `belongs_to` | `drill`, `skill` |

## Group

Reusable roster, optionally within an organisation. [Source](../../app/models/group.rb).

| Association | Names |
|---|---|
| `belongs_to` | `created_by`, `organisation` |
| `has_many` | `group_memberships`, `accounts`, `assessment_sessions` |

Statuses: `active`, `archived`.

Visibilities: `shared`, `private`.

## GroupMembership

Account membership of a group. [Source](../../app/models/group_membership.rb).

| Association | Names |
|---|---|
| `belongs_to` | `group`, `account` |

Roles: `owner`, `coach`, `member`.

Statuses: `pending`, `active`, `ended`.

## Log

Application event record with optional acting user. [Source](../../app/models/log.rb).

| Association | Names |
|---|---|
| `belongs_to` | `user` |
| `has_many` | `log_objects` |

## LogObject

Object context associated with an application log. [Source](../../app/models/log_object.rb).

| Association | Names |
|---|---|
| `belongs_to` | `log`, `object` |

## Organisation

Self-referencing organisation hierarchy, lifecycle and logo attachment. [Source](../../app/models/organisation.rb).

| Association | Names |
|---|---|
| `belongs_to` | `parent_organisation`, `created_by_account` |
| `has_many` | `organisation_memberships`, `active_memberships`, `members`, `child_organisations` |
| `has_one_attached` | `logo` |

Statuses: `active`, `archived`.

## OrganisationMembership

Organisation roster entry for an account or profile. [Source](../../app/models/organisation_membership.rb).

| Association | Names |
|---|---|
| `belongs_to` | `organisation`, `account`, `memberable` |

Roles: `owner`, `administrator`, `coach`, `member`.

Statuses: `pending`, `active`, `suspended`, `ended`.

## PlayerClaim

Reviewable request to link an existing player or coach profile. [Source](../../app/models/player_claim.rb).

| Association | Names |
|---|---|
| `belongs_to` | `claimable`, `player_profile`, `claimant_account`, `initiated_by_account`, `reviewed_by_account` |

Statuses: `pending`, `approved`, `rejected`, `cancelled`.

## PlayerCoach

Dated coach/player relationship preserved as history. [Source](../../app/models/player_coach.rb).

| Association | Names |
|---|---|
| `belongs_to` | `player_profile`, `coach_profile` |

## PlayerProfile

Independent volleyball player identity and history anchor. [Source](../../app/models/player_profile.rb).

| Association | Names |
|---|---|
| `belongs_to` | `created_by`, `created_by_account`, `account`, `merged_into_profile`, `merged_by_account` |
| `has_many` | `merged_profiles`, `claim_invitations`, `organisation_memberships`, `training_session_participants`, `assessment_session_participants`, `ranking_consolidation_rows`, `player_claims`, `groups`, `assessments`, `player_coaches`, `coaches` |

Statuses: `active`, `archived`.

Visibilities: `shared`, `private`.

## ProfileMerge

Audit record connecting retained source and canonical profiles. [Source](../../app/models/profile_merge.rb).

| Association | Names |
|---|---|
| `belongs_to` | `source_profile`, `canonical_profile`, `merged_by_account` |

## RankingConsolidation

Combined ranking across source assessment sessions. [Source](../../app/models/ranking_consolidation.rb).

| Association | Names |
|---|---|
| `belongs_to` | `assessment_definition`, `created_by`, `recalculated_by` |
| `has_many` | `consolidation_sessions`, `assessment_sessions`, `rows` |

Statuses: `draft`, `published`, `withdrawn`.

## RankingConsolidationRow

Consolidated result for one player. [Source](../../app/models/ranking_consolidation_row.rb).

| Association | Names |
|---|---|
| `belongs_to` | `ranking_consolidation`, `player_profile` |

## RankingConsolidationSession

Source session association and stored ranking snapshot. [Source](../../app/models/ranking_consolidation_session.rb).

| Association | Names |
|---|---|
| `belongs_to` | `ranking_consolidation`, `assessment_session` |

## Role

Global application role. [Source](../../app/models/role.rb).

| Association | Names |
|---|---|
| `has_many` | `user_roles`, `users` |

## Session

Persisted login session, optionally with API token and expiry. [Source](../../app/models/session.rb).

| Association | Names |
|---|---|
| `belongs_to` | `user`, `impersonated_user` |

## Skill

Reusable technical skill classified by category. [Source](../../app/models/skill.rb).

| Association | Names |
|---|---|
| `belongs_to` | `created_by`, `category` |
| `has_many` | `drill_skills`, `drills`, `video_references`, `videos` |

## TrainingFocus

Ordered session focus using a skill or custom text. [Source](../../app/models/training_focus.rb).

| Association | Names |
|---|---|
| `belongs_to` | `training_session`, `skill` |

## TrainingSession

Scheduled training with focuses, drills and participants. [Source](../../app/models/training_session.rb).

| Association | Names |
|---|---|
| `belongs_to` | `created_by` |
| `has_many` | `training_focuses`, `training_session_drills`, `drills`, `training_session_participants`, `player_profiles`, `assessments`, `video_references`, `videos` |

Statuses: `draft`, `scheduled`, `cancelled`, `completed`.

Visibilities: `shared`, `private`.

## TrainingSessionDrill

Ordered drill selection within a training. [Source](../../app/models/training_session_drill.rb).

| Association | Names |
|---|---|
| `belongs_to` | `training_session`, `drill` |

## TrainingSessionParticipant

Player participation and attendance for training. [Source](../../app/models/training_session_participant.rb).

| Association | Names |
|---|---|
| `belongs_to` | `training_session`, `player_profile` |

Statuses: `invited`, `confirmed`, `declined`, `attended`, `absent`.

## User

Login credentials, verification and global role predicates. [Source](../../app/models/user.rb).

| Association | Names |
|---|---|
| `has_one` | `account` |
| `has_many` | `sessions`, `user_roles`, `roles` |

## UserRole

User-to-role assignment. [Source](../../app/models/user_role.rb).

| Association | Names |
|---|---|
| `belongs_to` | `user`, `role` |

## Video

Normalized media resource and provider metadata. [Source](../../app/models/video.rb).

| Association | Names |
|---|---|
| `belongs_to` | `created_by`, `video_category` |
| `has_many` | `video_references`, `drills`, `skills`, `video_taggings`, `video_tags` |

## VideoCategory

Video library classification. [Source](../../app/models/video_category.rb).

| Association | Names |
|---|---|
| `has_many` | `videos` |

## VideoReference

Polymorphic contextual use of a video with timestamps. [Source](../../app/models/video_reference.rb).

| Association | Names |
|---|---|
| `belongs_to` | `video`, `referenced` |

## VideoTag

Video library label. [Source](../../app/models/video_tag.rb).

| Association | Names |
|---|---|
| `has_many` | `video_taggings`, `videos` |

## VideoTagging

Video-to-tag join. [Source](../../app/models/video_tagging.rb).

| Association | Names |
|---|---|
| `belongs_to` | `video`, `video_tag` |

## Supporting model code and framework records

[ProfileArchiveLifecycle](../../app/models/concerns/profile_archive_lifecycle.rb)
coordinates archive timestamps and invitation revocation. Sluggable supplies shared
slug behavior. VideoProviders and its adapters implement URL detection and provider
capabilities; they are not persisted domain entities.

Active Storage contributes attachment/blob/variant records. Solid Queue, Cache and
Cable supply infrastructure tables. Their configuration and migrations belong to
the runtime architecture, rather than new application-owned model files. See
[system architecture](system_architecture.md) and [source map](development_reference.md).
