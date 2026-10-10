# Architecture guide

This is the entry point for the implemented Beach Volleyball Hub architecture,
reviewed against the API and sibling React repository on 9 October 2026. It describes
source configuration, not verified production infrastructure. Earlier issue plans
remain useful history but may describe models that have since been replaced.

## Read the architecture

| Document | What it explains |
|---|---|
| [System architecture](system_architecture.md) | Components, deployment boundaries, request flow, jobs, storage and email. |
| [Model catalogue](models.md) | Every top-level application model, its responsibility, associations and declared states. |
| [Model relationships](model_relationships.md) | Domain diagrams, cardinalities, join records and polymorphic references. |
| [Identity and access](identity_and_access.md) | Users versus accounts versus profiles, ownership, claims and authorization. |
| [System and data lifecycles](system_lifecycle.md) | Registration, profile claims, archiving/merging, training, assessments and recovery. |
| [Development and source map](development_reference.md) | Where behavior lives, validation layers, tests and how to maintain these documents. |

## Core design

The React application calls a Rails JSON API backed by PostgreSQL. Rails also retains
server-rendered routes. Authentication is represented by `User` and `Session`;
`Account` holds the application identity and private contact details; independent
`PlayerProfile` and `CoachProfile` records carry volleyball history. A profile may
exist before it is linked to an account. A profile is not an authorization role.

Training combines reusable skills, drills and video references with scheduled
participants. Assessments can be individual or grouped into scored sessions;
ranking consolidations preserve published results. Archive, withdrawal and merge
operations preserve history where deleting a row would break its meaning.

There is **no current `Person` model** in `app/models`. References to Person in old
plans, comments or compatibility payloads do not define a new current table contract.
Use the catalogue and source links here when implementing a feature.

## Operational and design references

- [Local development and Vercel/Cloudflare/Render configuration](../LOCAL_VERCEL_RENDER_SETUP.md).
- [Database backup, restore and recovery](../DATABASE_BACKUP_AND_RESTORE.md).
- [Domain and DNS setup](../beachvolleyballproject_domain_setup.md).
- [Email transport documentation](../IDENTITY_226_mail_transport/README.md).
- [Account identity phase reports](../IDENTITY_228_ACCOUNT_CENTRIC/IDENTITY_228_PHASE_STATUS.md).
- [Profile lifecycle phase reports](../IDENTITY_255_PROFILES/IDENTITY_225_PHASE_STATUS.md).
- [Organisation design plan](../IDENTITY_231_REFACTOR_ORGANISATIONS/beachvolleyballproject-organisation-tree-membership-plan.md).
- [Assessment definitions plan](../IDENTITY_28_ASSESSMENT/ASSESSMENT_DEFINITIONS_PLAN.md).
- [Assessment sessions plan](../IDENTITY_28_ASSESSMENT/ASSESSMENT_SESSIONS_PLAN.md).

Keep architecture explanations here and detailed commands/secrets configuration in
the operational guides. None of these documents is a copy of live credentials.
