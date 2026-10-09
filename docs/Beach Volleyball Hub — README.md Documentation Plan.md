# Beach Volleyball Hub — README.md Documentation Plan

## Objective

Create a professional, accurate, maintainable `README.md` for the Beach Volleyball Hub.

The README should allow a new developer, maintainer, contributor, coach, or technical collaborator to understand:

- What the Beach Volleyball Hub is.
- What functionality currently exists.
- The overall application architecture.
- The relationship between the frontend and backend.
- The domain model.
- How authentication and authorization work.
- How to run the project locally.
- How the database is configured.
- How to run tests and quality checks.
- How the application is deployed.
- How training, assessment, drills, schedules, groups, tournaments, and other domain concepts work.
- Which functionality is implemented versus planned.

The README must be based on the **actual implementation in the repositories**.

Do not convert previous product discussions, future plans, or design ideas into claims that functionality already exists.

---

# 1. Project repositories

The Beach Volleyball Hub consists of two repositories:

- Frontend: `https://github.com/romalopes/beachvolleyballproject`
- Backend API: `https://github.com/romalopes/beachvolleyballproject_api`

The deployed architecture currently includes:

- React/Vite frontend.
- Ruby on Rails API.
- PostgreSQL database.
- Vercel frontend deployment.
- Render API deployment.

Verify all of these against the current repositories and deployment configuration before documenting them.

---

# 2. Repository documentation strategy

Create documentation appropriate to each repository.

## Frontend repository

`beachvolleyballproject`

The README should primarily explain:

- React application.
- Vite configuration.
- Frontend architecture.
- Pages and components.
- API integration.
- Authentication.
- Application state.
- Training UI.
- Assessment UI.
- Drill visualisation.
- Scheduling.
- Tournament functionality.
- Media.
- Offline/PWA functionality, if implemented.
- Environment variables.
- Testing.
- Production build.
- Vercel deployment.

## Backend repository

`beachvolleyballproject_api`

The README should primarily explain:

- Rails API.
- Domain model.
- Database.
- Authentication.
- Authorization.
- People/accounts.
- Players and coaches.
- Assessments.
- Assessment areas/criteria/categories/skills/drills.
- Training.
- Groups.
- Schedules.
- Tournaments.
- Media.
- API endpoints.
- Background jobs, if any.
- Testing.
- Database migrations.
- Render deployment.

## Optional shared documentation

If appropriate, identify future documentation that could live in:

```text
docs/
  architecture.md
  domain-model.md
  assessments.md
  drills.md
  training.md
  tournaments.md
  api.md
  deployment.md
  roadmap.md
```

Do not create these additional files unless explicitly requested.

---

# 3. Inspect the implementation first

Before writing the README, inspect the repository thoroughly.

Review the actual implementation, including:

## Frontend

- `package.json`
- lockfile
- Vite configuration
- React configuration
- routing
- pages
- components
- hooks
- services
- API clients
- authentication
- authorization
- state management
- forms
- validation
- offline/PWA implementation
- media handling
- drill visualisation
- training UI
- assessment UI
- tournament UI
- schedule UI
- tests
- linting
- formatting
- environment configuration
- build configuration

## Backend

- `Gemfile`
- `Gemfile.lock`
- Rails configuration
- routes
- models
- associations
- migrations
- schema
- controllers
- serializers
- services
- authorization policies
- authentication
- jobs
- mailers
- seeds
- tests
- environment configuration

## Infrastructure

Inspect:

- GitHub Actions.
- Render configuration.
- Vercel configuration.
- Database configuration.
- CORS.
- OAuth configuration.
- Environment examples.
- CI/CD.
- Backup workflows.
- Monitoring configuration, if any.

Do not expose secrets.

---

# 4. Identify the actual functionality

Before writing the README, build an inventory of functionality that currently exists.

Investigate the implementation of:

- Accounts.
- Users.
- People.
- Players.
- Coaches.
- Authentication.
- Roles.
- Player/coach relationships.
- Assessments.
- Assessment areas.
- Criteria.
- Categories.
- Skills.
- Drills.
- Drill media.
- Drill visual definitions.
- Training sessions.
- Training groups.
- Player schedules.
- Coach schedules.
- Tournaments.
- Tournament participation.
- Media/video.
- Likes.
- Comments, if implemented.
- Notifications, if implemented.
- Subscriptions, if implemented.
- Administrative functionality.
- Soft deletion/archive functionality.
- Offline/PWA functionality.

For each feature, determine whether it is:

- Fully implemented.
- Partially implemented.
- Backend-only.
- Frontend-only.
- Planned.
- Deprecated.

Do not document planned functionality as implemented.

---

# 5. Project introduction

Start the README with:

# Beach Volleyball Hub

Provide a concise description of the application.

Explain that the project is designed to support beach volleyball coaching, player development, training organization, assessment, drills, schedules, tournaments, and related workflows.

Do not overstate functionality.

Include:

- Current development status.
- Production application URL, if verified.
- Frontend repository.
- Backend repository.
- API URL, if publicly available.

---

# 6. Product capabilities

Create a feature overview organized around the actual product.

Potential categories include:

## Player development

- Player profiles.
- Coach profiles.
- Assessments.
- Assessment history.
- Skill development.
- Drill recommendations.

## Drills

- Drill creation.
- Drill categories.
- Training stages.
- Difficulty.
- Player requirements.
- Court visualisation.
- Drill steps.
- Media.
- Text annotations.
- Publication workflow.

## Training

- Training sessions.
- Training groups.
- Individual players.
- Coaches.
- Training schedules.
- Session levels.
- Session visibility.
- Player schedules.

## Tournaments

Document tournament functionality if implemented.

Include:

- Tournament creation.
- Tournament details.
- Events/categories.
- Teams.
- Players.
- Matches.
- Results.
- Standings.
- Scheduling.
- Offline functionality.

Only document concepts actually implemented.

## Media

- Videos.
- Media assets.
- External video links.
- Categories/tags.
- Playback.
- Timestamp references.
- Likes, if implemented.

## Administration

Document administrative features that actually exist.

---

# 7. Architecture

Explain the complete system architecture.

At minimum, document:

```text
React/Vite Frontend
        |
        | HTTPS / REST API
        v
Ruby on Rails API
        |
        v
PostgreSQL Database
```

If verified, include:

```text
Frontend → Vercel
API      → Render
Database → PostgreSQL provider
```

Also document external services where relevant:

- Google authentication.
- Email.
- Stripe.
- Media providers.
- Database provider.
- Cloudflare/R2.
- Other third-party services.

Only include services actually used by the current implementation.

If useful, create a Mermaid architecture diagram.

---

# 8. Technology stack

Create a table containing:

| Layer | Technology | Purpose |
|---|---|---|
| Frontend | React | User interface |
| Build | Vite | Frontend build |
| Backend | Ruby on Rails | API/business logic |
| Language | Ruby | Backend |
| Database | PostgreSQL | Persistent data |
| Frontend hosting | Vercel | Production frontend |
| API hosting | Render | Production API |

Determine actual versions from:

- `package.json`
- lockfiles
- `Gemfile`
- `Gemfile.lock`
- `.ruby-version`
- Node configuration
- Rails configuration

Do not guess versions.

---

# 9. Prerequisites

Document the software required for local development.

Include verified versions where possible:

- Git.
- Ruby.
- Bundler.
- Rails.
- Node.js.
- npm.
- PostgreSQL/database tooling.
- Any other required CLI tools.

---

# 10. Local installation

Provide complete setup instructions.

## Backend

Document:

1. Clone repository.
2. Install Ruby dependencies.
3. Configure environment variables.
4. Configure database.
5. Create database if required.
6. Run migrations.
7. Load seed data if applicable.
8. Start Rails server.

## Frontend

Document:

1. Clone repository.
2. Install Node dependencies.
3. Configure environment variables.
4. Configure API URL.
5. Start Vite development server.
6. Open application.

All commands must be based on the actual project.

---

# 11. Environment variables

Document all environment variables actually used.

Create a table:

| Variable | Application | Required | Purpose |
|---|---|---:|---|
| `VITE_API_BASE_URL` | Frontend | Yes | API base URL |
| `DATABASE_URL` | Backend | Yes | PostgreSQL connection |
| `RAILS_MASTER_KEY` | Backend | Depends | Rails credentials |
| OAuth variables | Backend/frontend | Depends | Authentication |
| Stripe variables | Backend | Depends | Payments |

Replace these examples with the actual variables found in the repository.

For every variable:

- Find its usage.
- Explain its purpose.
- Identify whether it is required.
- Provide a safe example where possible.

Never include real secrets.

---

# 12. Domain model

This section is particularly important for Beach Volleyball Hub.

Explain the major domain concepts and their relationships.

Where implemented, investigate:

```text
Person
 ├── Account
 ├── Player
 └── Coach
```

Explain the distinction between:

- Authentication identity.
- Person.
- Player.
- Coach.
- User/account.
- Application roles.

Do not assume the conceptual model from previous planning is identical to the current implementation. Verify the actual models.

---

# 13. Player and coach model

Document how the system represents:

- People.
- Players.
- Coaches.
- Accounts.
- Player profiles.
- Coach profiles.
- Relationships between players and coaches.
- Historical relationships.
- Permissions.

If the implementation supports a person being both a player and coach, document it.

If that is only planned, place it in the roadmap instead.

---

# 14. Authentication and authorization

Document:

- Registration.
- Login.
- Logout.
- Social authentication.
- Account creation.
- Roles.
- Permissions.
- Protected API endpoints.
- Protected frontend routes.
- Administrative access.
- Account lifecycle.

If roles such as:

- Guest.
- Player.
- Coach.
- Admin.

exist, verify them against the implementation before documenting them.

Do not assume that a person's volleyball characteristics and their application permissions are the same thing.

---

# 15. Assessment system

The assessment system deserves its own section.

Document the actual hierarchy implemented.

Where applicable, investigate the relationship between:

```text
Assessment Area
      |
   Criterion
      |
   Category
      |
    Skill
      |
    Drill
```

Verify the actual implementation before documenting this hierarchy.

Document:

- Assessment definitions.
- Criteria.
- Categories.
- Skills.
- Drills.
- Scoring scale.
- Minimum/maximum values.
- Steps/increments.
- Weighting.
- Included versus excluded criteria.
- Assessment history.
- Assessment ownership.
- Coach permissions.
- Player visibility.
- Archived definitions.
- Historical assessment preservation.

Explain normalization/weighting rules if they are implemented.

---

# 16. Drill system

Document the drill model.

Investigate and describe actual support for:

- Drill title.
- Description.
- Skill/category.
- Training stage.
- Difficulty.
- Minimum players.
- Maximum players.
- Ideal players.
- Player parity.
- Steps.
- Court diagrams.
- Media.
- Video.
- Annotations/text.
- Tags.
- Publication status.
- Creator.
- Curator/review workflow.
- Versions.

If the application supports visual drill definitions, explain how they are represented.

Do not call the movable text element "legend" if the implementation uses another term. Use the actual domain terminology.

---

# 17. Drill publication workflow

If implemented, document the publication lifecycle.

For example, investigate whether the system supports concepts such as:

```text
Draft
Private
Unlisted
Public candidate
Public
Rejected
Archived
```

Verify the actual states.

Explain:

- Who can create drills.
- Who can edit them.
- Who can publish them.
- Who can curate them.
- What happens after rejection.
- What happens after editing a published drill.
- Whether versions are retained.

Only document implemented behavior.

---

# 18. Training system

Document how training sessions are represented.

Investigate:

- Training session.
- Coach.
- Group.
- Individual players.
- Date/time.
- Location.
- Level.
- Gender/category.
- Training drills.
- Training stages.
- Notes.
- Visibility.
- Attendance.
- Schedule.

If training levels such as:

```text
B
BB
BBB
A
AA
AAA
```

exist in the code, document them.

Also document any:

```text
Mix
Men
Women
```

classification if implemented.

Do not hard-code these concepts in the README if they are only planned.

---

# 19. Groups

Document the actual group model.

This is an important domain concept because a group does not necessarily represent an official club.

Investigate whether the implementation distinguishes between:

- Training groups.
- Player-created groups.
- Coach-created groups.
- Clubs.
- Organizations.
- Informal groups.
- Cities/regions.
- Group visibility.

Explain the actual implementation.

If there is currently no club/organization concept, do not claim that there is one.

If group discovery or visibility is planned, document it as future functionality.

---

# 20. Scheduling

Document the scheduling architecture.

Explain:

- Coach-created sessions.
- Group schedules.
- Individual player schedules.
- Invitations.
- Visibility.
- Recurring sessions, if implemented.
- Attendance.
- Conflicts.
- Calendar representation.

Pay particular attention to privacy.

If training sessions are intended for selected players rather than the entire internet, document the actual authorization and visibility implementation.

Do not claim privacy guarantees that have not been verified.

---

# 21. Tournament system

The tournament system should receive the same level of documentation as Training and Assessment.

Document the actual implementation of:

- Tournaments.
- Tournament events.
- Divisions/categories.
- Teams.
- Players.
- Matches.
- Courts.
- Schedules.
- Results.
- Standings.
- Brackets.
- Rankings.
- Registration.
- Check-in.
- Tournament state.
- Offline operation, if implemented.

If tournament functionality is designed to work offline, document:

- What data is available offline.
- What actions can be performed offline.
- Local persistence.
- Synchronization.
- Conflict handling.
- Reconnection behavior.

Only document offline behavior that actually exists.

---

# 22. Offline/PWA architecture

If the project contains PWA/offline functionality, give it its own section.

Document:

- Service worker.
- Cache strategy.
- Offline pages.
- Local storage/indexed database.
- Data synchronization.
- Offline writes.
- Conflict resolution.
- Authentication behavior offline.
- Training offline support.
- Assessment offline support.
- Tournament offline support.

Clearly distinguish between:

- Offline UI availability.
- Offline read access.
- Offline creation/editing.
- Offline synchronization.

Do not describe the application as "fully offline" unless that is demonstrably true.

---

# 23. Media and video

Document media functionality.

Investigate:

- Media assets.
- Video URLs.
- YouTube.
- Instagram.
- Other external video sources.
- Future uploads.
- Storage.
- Playback.
- Timestamp references.
- Categories.
- Tags.
- Likes.

If video uploads are not implemented yet, state that clearly.

---

# 24. Account and user lifecycle

Document:

- Account creation.
- Person creation.
- Player creation.
- Coach creation.
- Account linking.
- Authentication.
- Invitations.
- Account deactivation.
- Soft deletion.
- Archiving.
- Historical data preservation.

If soft deletion is planned rather than implemented, put it in the roadmap.

---

# 25. API documentation

For the Rails API, document the actual endpoints.

Start with:

- Base URL.
- API version.
- Authentication.
- Error format.

Then create endpoint tables.

Example:

| Resource | Method | Endpoint | Authentication |
|---|---|---|---|
| Players | GET | `/api/v1/players` | ... |
| Players | POST | `/api/v1/players` | ... |
| Assessments | GET | `/api/v1/assessments` | ... |
| Drills | GET | `/api/v1/drills` | ... |
| Training | POST | `/api/v1/trainings` | ... |
| Tournaments | GET | `/api/v1/tournaments` | ... |

These are examples only.

Generate the actual table from Rails routes/controllers.

Document important:

- Parameters.
- Request bodies.
- Responses.
- Validation.
- Authorization.
- Pagination.
- Filtering.
- Sorting.

If OpenAPI/Swagger exists, link to it instead of duplicating everything.

---

# 26. Frontend API integration

Document:

- API base URL.
- API client.
- Authentication handling.
- Error handling.
- Request handling.
- Environment configuration.

Explain how the frontend connects to:

- Local API.
- Development API.
- Production API.

---

# 27. Database

Document:

- PostgreSQL.
- Database setup.
- Migrations.
- Seeds.
- Important extensions if any.
- Development database.
- Production database at a high level.

Document the actual commands for:

- Creating the database.
- Running migrations.
- Loading seeds.
- Resetting development data, if safe.

Do not document destructive commands without clearly identifying their consequences.

---

# 28. Testing

Document the actual testing infrastructure.

Include:

- Backend tests.
- Frontend tests.
- Model tests.
- Request/API tests.
- Component tests.
- Integration tests.
- Offline/PWA tests.
- Tournament tests.
- Assessment tests.
- Linting.
- Formatting.
- Build verification.

Use the actual commands from the project.

---

# 29. CI/CD

Inspect GitHub Actions and document the actual workflows.

Include, where applicable:

- Tests.
- Linting.
- Builds.
- Database checks.
- Deployment.
- Security checks.
- Database backups.
- Backup freshness checks.
- Restore/testing workflows.

Do not expose GitHub secrets.

If the project has database backups to Cloudflare R2, document the workflow at a safe architectural level without exposing:

- R2 credentials.
- Database URLs.
- Encryption keys.
- GitHub secrets.

---

# 30. Deployment

Document the actual deployment architecture.

If verified, explain:

```text
Vercel
React/Vite frontend
        |
        | HTTPS
        v
Render
Rails API
        |
        v
PostgreSQL
```

Document:

- Frontend hosting.
- API hosting.
- Database provider.
- Production URLs.
- Build commands.
- Environment variables.
- CORS.
- OAuth origins.
- Database migrations.
- Deployment process.
- Logs.
- Rollback considerations.

If Render's free service behavior affects development or production, document it only if relevant to the current deployment.

---

# 31. Security

Include a concise security section.

Document relevant implemented mechanisms:

- Authentication.
- Authorization.
- CORS.
- Input validation.
- API authorization.
- Database security.
- Secret management.
- OAuth configuration.
- Rate limiting, if implemented.
- Account deletion/deactivation.
- Privacy controls.
- Backup security.

Do not expose secrets.

Do not claim a security property unless it is actually implemented.

---

# 32. Privacy and visibility

Because the application contains player and training information, document the actual visibility model.

Explain who can see:

- Player profiles.
- Coach information.
- Assessments.
- Coach comments.
- Training sessions.
- Group membership.
- Tournament information.
- Media.
- Private drills.
- Public drills.

If some information is intended to be private but the implementation does not currently enforce that, identify it as a limitation rather than claiming it is protected.

---

# 33. Development workflow

Document:

- Branching.
- Commits.
- Pull requests.
- Testing.
- Code review.
- Database migrations.
- API changes.
- Frontend/backend coordination.

Only document existing conventions as facts.

If conventions have not yet been established, present recommendations as recommendations.

---

# 34. Roadmap

Separate the project status into:

## Implemented

Current functionality.

## In progress

Features currently being developed.

## Planned

Future functionality.

## Known limitations

Current technical/product limitations.

Potential future areas may include:

- Expanded offline support.
- Tournament functionality.
- Advanced assessment analytics.
- Drill recommendation.
- Video uploads.
- S3/R2 media storage.
- Improved group discovery.
- Organization/club visibility.
- Subscription functionality.
- Additional mobile/PWA capabilities.

However, these should only be included after checking whether they are already implemented.

---

# 35. Contributing

Document:

1. Local setup.
2. Branch creation.
3. Feature development.
4. Tests.
5. Linting.
6. Pull request.
7. Code review.
8. Database migration considerations.

Make the instructions specific to the project.

---

# 36. License

Inspect the repository for a license.

If one exists, document it.

If none exists:

- Do not invent one.
- State that licensing has not yet been defined, if appropriate.

---

# 37. Useful links

Include verified links to:

- Production frontend.
- API.
- Frontend repository.
- Backend repository.
- Issue tracker.
- Documentation.
- Relevant external services.

Do not include private administrative links unless the README is intended for internal use.

---

# 38. Documentation quality requirements

The final README must be:

- Professional.
- Accurate.
- Developer-friendly.
- Easy to navigate.
- Maintainable.
- Based on the current implementation.

Use:

- Tables.
- Code blocks.
- Mermaid diagrams.
- Architecture diagrams.
- Internal links.
- Clear headings.

Avoid:

- Marketing claims.
- Unsupported functionality.
- Outdated instructions.
- Duplicated information.
- Secrets.
- Private credentials.
- Speculative architecture.

---

# 39. Validation

Before finalizing the README:

Verify:

- Technology versions.
- Installation commands.
- Environment variables.
- Database commands.
- API endpoints.
- Authentication.
- Authorization.
- Domain relationships.
- Assessment model.
- Drill model.
- Training model.
- Group model.
- Tournament model.
- Offline behavior.
- Testing commands.
- Build commands.
- Deployment configuration.
- URLs.
- Mermaid syntax.
- Markdown formatting.

Where possible, execute the documented commands.

Do not claim a command was tested if it was only inferred from the repository.

---

# 40. Documentation-only constraint

This task is documentation-only.

Do not modify:

- Application code.
- Database schema.
- Migrations.
- API behavior.
- Frontend behavior.
- Authentication.
- Authorization.
- Deployment configuration.
- GitHub Actions.
- Environment variables.

Only modify the README or other documentation files explicitly required for this task.

---

# 41. Final report

After completing the README, report:

## README created/updated

Give the exact path.

## Sections added

Summarize the major sections.

## Implementation verified

List the important parts of the application that were inspected.

## Information that could not be verified

Clearly identify documentation gaps.

## Commands validated

List commands actually executed.

Separate these from commands that were only documented.

## Documentation gaps

Identify information that should eventually be documented elsewhere.

## Recommended future documentation

Suggest additional documentation such as:

```text
CONTRIBUTING.md
CHANGELOG.md
docs/architecture.md
docs/domain-model.md
docs/assessments.md
docs/drills.md
docs/training.md
docs/tournaments.md
docs/api.md
docs/deployment.md
docs/roadmap.md
```

Do not create these additional files unless explicitly requested.