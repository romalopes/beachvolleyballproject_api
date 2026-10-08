# Identity Phase 6: Multiple CoachProfiles

## Status

Complete. Phase 2 had already removed the unique index on `coach_profiles.person_id`; this phase completed the application behavior and explicit attribution for a Person with several coach records.

## Architecture decision

`OrganisationMembership` and `GroupMembership` remain Person-level records. They describe where a Person belongs and the Person's organisation/group role; they do not identify which CoachProfile is acting. `Assessment`, `AssessmentSession`, and `PlayerCoach` already reference a specific CoachProfile, so those records are the coaching-attribution context. No extra `CoachMembership` table or duplicated organisation/group foreign keys will be added in this phase.

CoachProfiles remain independently managed domain records. They do not grant application permissions. Existing User roles continue to gate access. A signed-in Person may select any of their own active CoachProfiles when creating coach-attributed work; staff may attribute work to another coach only through existing oversight rules.

## Existing behavior to preserve

- `Person` may have zero, one, or many CoachProfiles; each CoachProfile still requires a Person.
- Multiple profile rows never create or merge Persons.
- Profile records are archived rather than hard deleted because assessment and coaching history reference their IDs.
- The unique Account-per-Person rule remains unchanged.
- Existing singular API fields remain transitional compatibility fields while plural IDs/profile summaries are added.

## Delivered

- `/api/v1/me` returns all CoachProfiles and IDs, with the first active profile retained in the legacy singular field.
- Assessment defaulting, explicit attribution, `mine` filtering, and stakeholder visibility now recognize every CoachProfile belonging to the signed-in Person. Explicit attribution to another Person remains limited to existing curator/admin oversight.
- The SPA refreshes `/me` after login, registration, password reset, and impersonation transitions so the profile collection is available immediately.
- Coach relationship creation can choose among the signed-in Person's active CoachProfiles. Coach ownership checks and assessment edit checks recognize all of that Person's profile IDs.
- Coach creation flows and admin promotion can add another CoachProfile to an existing Person.
- Existing organization/group memberships remain Person-scoped; no redundant context join table was introduced. Assessment, session, and coaching-period records retain the selected CoachProfile ID.
- Updated the stale identity overview and added tests for zero/one/multiple profiles and preservation of Account, PlayerProfiles, memberships, sibling profiles, and historical attribution.

## Verification

1. A Person can have zero, one, or several valid CoachProfiles.
2. A coach may create an assessment attributed to any of their own active profiles, but cannot spoof another Person's profile; curator/admin override behavior remains intact.
3. Profile archive/restore keeps other profiles, Account, PlayerProfiles, organisation/group memberships, and historical records unchanged.
4. Existing response fields remain compatible; new responses expose all own profile IDs/details.
5. Full backend suite: 1,358 runs, 5,404 assertions, 0 failures/errors, 1 existing skip.
6. Full frontend suite: 854 tests across 78 files passed.
7. `npm run build` passed; Vite emitted its existing large-chunk advisory.

## Follow-up boundary

This phase does not add a context-membership table or infer that each organisation/group membership needs a separate CoachProfile. Cross-domain consolidation remains Phase 7–8; broad API and UI work remains Phases 11–12; the security review remains Phase 13.
