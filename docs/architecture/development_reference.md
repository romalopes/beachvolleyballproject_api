# Development and source map

[Architecture index](architecture.md)

## Where to change behavior

| Layer | Location | Responsibility |
|---|---|---|
| Browser application | Sibling frontend `src/`, particularly `src/api.ts` | Routing, forms, UI state and API requests. |
| HTTP contract | [Routes](../../config/routes.rb), [API controllers](../../app/controllers/api/v1) | Endpoints, permitted input, action authorization and response status. |
| Authentication | [Authentication concern](../../app/controllers/concerns/authentication.rb) | Cookie/bearer session lookup and creation. |
| Domain records | [Models](../../app/models) | Associations, validation, scopes and persistence callbacks. |
| Coordinated operations | [Services](../../app/services) | Claims, merges, publication, ranking and delivery workflows. |
| Database contract | [Schema](../../db/schema.rb), [migrations](../../db/migrate) | Columns, indexes, foreign keys and check constraints. |
| Runtime configuration | [Config](../../config) | Database, storage, queues, email and environment choices. |
| Operational automation | [Workflows](../../.github/workflows) | CI and backup/restore/freshness automation. |
| Tests | [API tests](../../test), frontend `src/**/*.test.*` | Regression evidence for contracts and domain rules. |

## Validation and history

Strong parameters limit writable HTTP attributes. Models enforce per-record rules.
Services use transactions/locks for operations spanning records. Database constraints
provide an additional boundary against duplicates and invalid references. Polymorphic
references and JSON snapshots require application-level checks beyond simple foreign
keys; ProfileDeletionBlocker and ProfileMergeService demonstrate this distinction.

`created_by` can mean audit attribution rather than exclusive management rights:
training sessions are managed by role, while profile ownership has explicit account
rules. Do not copy one resource's authorization rule to another because both have
a creator column.

AppSetting provides stored configuration; Log/LogObject and AdminActivity record
operational/audit information. They do not replace database backups or establish
that every action is audited. Inspect controller/service use when adding a new action.

## Verify a change

Run targeted Rails tests under `test/` for the affected model, service and controller;
run relevant frontend tests with `npm test` in the frontend repository. Run
`npm run build` for frontend type/build validation where appropriate. Configure a
separate test database before running Rails tests; never point test setup at the
production database. See the setup guide for dependencies and environment variables.

Architecture documentation is based on static source review, not a claim that the
full system or all deployment combinations were executed while writing it. Update
the model catalogue, diagrams and lifecycle text together when adding/removing models
or changing transitions. Keep the index linked from the README. Mark historical
plans as historical when their terminology differs from current source.
