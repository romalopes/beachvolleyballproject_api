# Identity Phase 13: Security audit

## Status

Complete. The identity-changing API paths were reviewed for account takeover, IDOR, enumeration, token disclosure, unauthorized profile access, and organisation/group boundary bypass. One invitation-link exposure was remediated. No migrations were needed.

## Findings and actions

| Severity | Finding | Affected area | Action and regression coverage |
| --- | --- | --- | --- |
| Medium — fixed | Phase 12 placed the one-time invitation bearer token in a query parameter. Query strings can be copied into referrer headers and intermediary request logs. | Player claim invitation generation and redemption UI | New links use the URL fragment (`/identity#claim_token=…`), which browsers do not send in HTTP requests or referrers. The page accepts the old query form during transition and removes either token form after successful redemption. UI tests cover fragment redemption, login handoff, and legacy query parsing. Server parameter filtering already filters token parameters. |
| Low — accepted product behavior | `include_private=1` lets authenticated training managers list profiles marked private, including their identity/contact fields. | Player/coach catalogue endpoints | This flag is an explicit catalogue option and is used by roster, assessment, and relationship pickers. Visibility is documented in the models and UI as a soft presentation preference, not an authorization boundary; a profile's direct detail endpoint still applies `visible_to_user?`. Do not use profile visibility to store confidential information. The separate show/update checks and catalogue visibility tests cover direct access. |
| Low — accepted deployment configuration | API CORS allows any origin, while the SPA authenticates JSON requests using an explicit bearer header. | `ApplicationController#set_cors_headers`, `Authentication` | Cross-origin cookie credentials are not enabled. A third-party origin cannot make an authenticated API call without obtaining the bearer token. Token confidentiality therefore depends on protecting the SPA origin and account session; consider origin allow-listing if the deployment model changes. |

## Controls verified

### Claims and candidate discovery

- Candidate discovery requires authentication and an active linked Person. It derives matching data from the caller's Person rather than accepting a search term or target Person ID.
- Candidate payloads contain only the profile ID, display name, match classification, and `result_type: candidate`. The candidate service does not create or link records.
- Claim creation derives the claimant from the authenticated account, checks that the target profile is visible and claimable, and uses the model/service uniqueness guards to prevent duplicate pending requests.
- Claim show and cancellation are scoped to the claimant; unauthorized IDs return a concealed not-found response. Approval and rejection are limited to an admin or the creating coach, require a linked reviewer Person, and reject self-review. Rejection requires a reason.
- The claims index combines caller-owned claims with only the review queue the caller may access. It does not return another coach's review data.

### Invitations

- Tokens are generated with 256 bits of randomness, stored only as SHA-256 digests, returned only on creation, and absent from status serializers.
- Tokens are single-use, expire after seven days, and are rejected after revoke, use, expiry, or profile linking. Redemption creates a reviewable claim; it does not directly attach the profile to the claimant.
- Create and redeem actions are rate-limited. Invalid redemption states share one generic error message. Invitation show/revoke conceal records not owned by the caller; creation/list/revoke also require content-creator authorization.
- Raw tokens are filtered from Rails parameter logs. New browser links carry tokens in fragments and clear them after redemption.

### Coach profiles and attribution

- Coach profile listing and direct read honor visibility. A user cannot change another owner's visibility setting.
- Assessment writes validate submitted coach profile IDs: a coach can attribute to their own active profile; curator/admin oversight can attribute more broadly. Assessment-session creation similarly checks coach-of-record authority.
- Multiple profiles remain separate records. No submitted profile ID changes a Person's account or profile ownership by itself.

### Consolidation and account reassignment

- Every consolidation route requires authentication and checks the real administrator, including during impersonation. The operation records the real administrator as performer.
- Source/canonical IDs are loaded server-side. The service locks both people, rechecks state, rejects cycles and already-merged people, and runs reassignment, conflict resolution, and audit creation in one transaction.
- Two Account records are a blocking conflict. Membership conflicts require an exact set of valid keep-record decisions with nonblank, bounded reasons; discarded snapshots and reasons are retained in the audit.
- Audit retrieval is admin-only. No public endpoint accepts an account ID for direct reassignment.

### Organisation and group boundaries

- Nested organisation membership writes are checked against the target Person, original organisation, and destination organisation. Foreign membership IDs are rejected; only pending membership invitations may be destroyed.
- Group and organisation membership mutation routes validate the caller's relevant ownership/administrator membership and container compatibility. Person consolidation is the only cross-container bulk reassignment path and is admin-only/audited.
- Profile endpoints prevent re-pointing a profile at another Person. Linking and multi-profile changes go through their explicit workflows.

## Verification

- Identity security controller/service regression suites: **159 tests, 582 assertions, 0 failures, 0 errors, 0 skips**.
- Identity page tests: **6 passed**, including token fragment handling, login handoff, legacy query links, unauthorized presentation, API errors, and account-conflict blocking.
- Frontend production build passed. The bundler reports the existing large JavaScript chunk advisory.
- Ruby syntax checks and `git diff --check` passed.

## Changed files

- `beachvolleyballproject/src/pages/PlayerDetail.tsx`: issue/share the invitation link with its token in the fragment.
- `beachvolleyballproject/src/pages/Identity.tsx`: redeem fragment or legacy query token, preserve it through sign-in, and clear it after redemption.
- `beachvolleyballproject/src/pages/Identity.test.tsx`: invitation-link security coverage.

## Residual risks

- A valid one-time invitation URL is a bearer credential until it expires, is revoked, or is redeemed. Share it only with the intended player; the server's one-use and expiry checks remain authoritative.
- The soft `private` visibility setting is not a confidentiality control for training managers. Store sensitive identity data only where the relevant role authorization applies.
- Browser XSS or compromise of the authenticated SPA can expose a user's bearer session; this audit did not replace the separate application-wide security review in the remaining plan.
