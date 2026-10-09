# Model relationships

[Architecture index](architecture.md) · [Complete catalogue](models.md)

These diagrams show domain relationships rather than every SQL column. `o|` means
zero or one and `o{` means zero or many. Optional associations, polymorphic references,
validation and database constraints must be read together; Rails `has_one` alone
does not create a child row.

## Identity, organisations and profiles

```mermaid
erDiagram
  User ||--o| Account : has
  User ||--o{ Session : authenticates
  User ||--o{ UserRole : receives
  Role ||--o{ UserRole : defines
  Account ||--|| ContactDetail : requires
  Account ||--o| AccountAddress : stores
  Account o|--o{ PlayerProfile : links
  Account o|--o{ CoachProfile : links
  PlayerProfile ||--o{ PlayerCoach : participates
  CoachProfile ||--o{ PlayerCoach : coaches
  Organisation o|--o{ Organisation : parent_of
  Organisation ||--o{ OrganisationMembership : records
  Organisation o|--o{ Group : contextualizes
  Group ||--o{ GroupMembership : contains
  Account ||--o{ GroupMembership : joins
```

`OrganisationMembership.memberable` is a polymorphic reference to exactly one
Account, PlayerProfile or CoachProfile. It also retains optional `account_id`
compatibility. The uniqueness scope is organisation + memberable type + memberable
ID. A group roster instead joins Group directly to Account. Group-to-organisation
association is optional; memberships and assessment rosters are different records.

`PlayerCoach` is a dated coaching period, not an assessment permission grant.
Ending a period preserves it; a later period can be recorded without deleting history.
`PlayerClaim` and `ClaimInvitation` target either profile kind. `ProfileMerge` records
source and canonical profiles of the same kind, plus the acting account and reason.

## Content and training

```mermaid
erDiagram
  Category ||--o{ Skill : classifies
  Skill ||--o{ DrillSkill : develops
  Drill ||--o{ DrillSkill : includes
  TrainingSession ||--o{ TrainingSessionDrill : schedules
  Drill ||--o{ TrainingSessionDrill : selected
  TrainingSession ||--o{ TrainingFocus : focuses
  Skill o|--o{ TrainingFocus : referenced
  TrainingSession ||--o{ TrainingSessionParticipant : invites
  PlayerProfile ||--o{ TrainingSessionParticipant : attends
  Video ||--o{ VideoReference : reused
  VideoCategory o|--o{ Video : classifies
  Video ||--o{ VideoTagging : tagged
  VideoTag ||--o{ VideoTagging : labels
```

A TrainingFocus uses a skill or custom text. A VideoReference's polymorphic
`referenced` target is a Skill, Drill or TrainingSession; timestamps and context
belong on the reference. Deleting a reference does not delete its shared Video.
Deleting a Video destroys its references, so that operation has broader consequences.

## Assessment and ranking

```mermaid
erDiagram
  AssessmentDefinition ||--o{ AssessmentCategory : configures
  AssessmentCategory ||--o{ Criterion : details
  AssessmentDefinition o|--o{ Assessment : structures
  Assessment ||--o{ AssessmentCategoryScore : records
  AssessmentCategory ||--o{ AssessmentCategoryScore : scored
  Criterion o|--o{ AssessmentCategoryScore : selected
  PlayerProfile ||--o{ Assessment : receives
  CoachProfile ||--o{ Assessment : authors
  AssessmentDefinition ||--o{ AssessmentSession : applied
  CoachProfile ||--o{ AssessmentSession : conducts
  Group o|--o{ AssessmentSession : supplies_roster
  AssessmentSession ||--o{ AssessmentSessionParticipant : includes
  PlayerProfile ||--o{ AssessmentSessionParticipant : assessed
  AssessmentSession o|--o{ Assessment : groups
  AssessmentDefinition ||--o{ RankingConsolidation : defines
  RankingConsolidation ||--o{ RankingConsolidationSession : combines
  AssessmentSession ||--o{ RankingConsolidationSession : sourced
  RankingConsolidation ||--o{ RankingConsolidationRow : ranks
  PlayerProfile ||--o{ RankingConsolidationRow : placed
```

An AssessmentCategory selects a catalogue Category or a CategoryCustom; the model
validates its source. An Assessment may also refer to a training session and may
use a standalone category instead of an AssessmentDefinition. Individual category
scores can be criterion-specific; partial unique indexes distinguish those from
category-level scores.

Rankings include stored source snapshots and result rows. JSON snapshots are not
ordinary foreign keys: profile merging intentionally avoids rewriting all historical
JSON. Referential checks must therefore include both associations and snapshot use.

## Deletion is domain-specific

Models use a mixture of destroy, nullify and restrict dependencies. For example,
removing a training session destroys its roster/focus/drill links but nullifies its
assessments' training-session link. Profiles restrict deletion when protected history
exists. Controller/service rules can be stricter than association declarations.
Consult [lifecycles](system_lifecycle.md) before choosing a deletion operation.
