# Identity Phase 16: Making claim invitations reachable

## The problem this phase fixes

Phase 5 shipped a complete, tested invitation lifecycle: one-time tokens, SHA-256
digests, expiry, revocation, rate limits, and a Phase 3 approval step. The API,
the model, the service and the client all worked.

**None of it could be reached from the UI.** A coach following the documented
steps — open a player, look for "Create claim invitation" — would never find the
button, because of two independent defects.

### 1. The invitation branch was unreachable

The panel rendered only in the `else` of `player.person`:

```tsx
const canInvite = !player.person && user && (admin || (coach && player.created_by?.id === user.id));
```

But the only way the SPA recorded a player was `PersonCreatePanel`, which
required a first name and always submitted `person: { ... }`. The API then
created a `Person` **and** a `PlayerProfile` already linked to it
(`PersonCreationService` stamps `creation_source: "coach_created"`).

So every player a coach recorded had `person_id` set, the `else` branch never
executed, and the button never rendered. This was not a permissions or
navigation problem — the state the feature requires could not be produced.

The backend has always supported it: `PlayerProfile` validates `display_name`
presence precisely when `person.nil?`, and `PlayerInput` documents `display_name`
as *"Required when recording a player before their Person is known"*. The SPA
simply never exercised that branch.

### 2. Invitations could not be recovered or revoked

The raw token is returned exactly once, and the page held it in React state, so
a refresh silently destroyed the only copy. `GET /player_claim_invitations` and
`POST /player_claim_invitations/:id/revoke` existed on the API and in `api.ts`
but **no component called them**. A coach who lost a link had no way to see that
one was still live, and no way to kill it.

There was also no entry point on `/identity` — the page a coach would naturally
open — so the whole feature was reachable only by knowing a detail-page URL.

## What changed

### Recording a player without an account

`PersonProfileForm` gained an `identityMode` prop. In `placeholder` mode it asks
for a display name instead of contact details and reports a null `person`;
`PersonCreatePanel` offers it as an explicit radio choice and omits `person` and
`person_id` from the payload.

Selecting an existing person always wins over placeholder mode — a profile linked
to a known `Person` is the better record. The mode is **player-only**: a
`CoachProfile` requires a `Person` (Phase 2).

`PersonProfileEditPage` previously refused any profile without a `Person`, so a
placeholder could never be corrected. It now edits a player placeholder by
display name and still refuses a coach one.

### A durable invitation panel

The inline block was extracted to `components/people/ClaimInvitationPanel.tsx`,
which loads the safe metadata on mount and therefore answers "is there a live
invitation?" after any refresh. It revokes through the endpoint that already
existed.

Every unavailable state now explains itself: a linked profile says no invitation
is needed; a non-owner coach and an owner without a linked `Person` each get
their specific reason. The permission rule mirrors the API's `profile_owner?`.

### Address-restricted invitations

An invitation could previously only be a bearer token, which answers "how does a
coach invite a *specific* person?" only by trusting whoever holds the link.

`invitee_email` is an optional column on `player_claim_invitations`:

- **NULL** — an open one-time token, the only option for a placeholder profile
  (it has no `Person`, so no address).
- **a value** — only a signed-in `Person` whose `email` matches may redeem.

Values are normalized (trimmed, downcased) on write, so redemption is an exact
comparison. A mismatched address returns the **same generic `INVALID_MESSAGE`**
as an invalid token, so the endpoint cannot be used to discover whether an
address was invited. A failed attempt does not consume the invitation.

The unique index is per `(player_profile_id, invitee_email)`: the existing
"one active invitation per profile" index already bounds live links, and a club
may legitimately invite one person to several profiles.

### Optional delivery

`PlayerClaimInvitationsMailer` sends the link to the invited address, modelled on
`EmailVerificationsMailer`, with the token in the **URL fragment** so it never
reaches an access log or `Referer` header (Phase 13).

Delivery is additive and never required:

- Nothing is sent unless the invitation names an address — an open invitation
  has no recipient.
- It is gated by `CLAIM_INVITATION_EMAIL_ENABLED`, **defaulting to false**, so a
  development or misconfigured deployment cannot mail a real address it does not
  own.
- `PlayerClaimInvitationDelivery` rescues and logs delivery failures. The
  invitation and its link already exist and work; being able to invite a player
  must not depend on the SMTP relay being up.

### A coach entry point on `/identity`

`ClaimInviteList` lists the viewer's own unlinked profiles (`GET /players?mine=1`
filtered to `person_id === null`) and creates an invitation in one click, so the
flow no longer requires knowing a detail-page URL.

## Verification

Backend: `bin/rails test` — **1,394 tests, 5,631 assertions, 0 failures**
(one pre-existing unrelated skip).

New backend coverage:

- `PlayerClaimInvitationServiceTest` — address match, mismatch refused with the
  generic message and the invitation still usable, open bearer token, malformed
  address rejected.
- `PlayerClaimInvitationsControllerTest` — address accepted and normalized,
  malformed rejected, a restricted invitation refuses a different address and
  stays active, the invited address redeems.

Frontend: `npm test` — **872 tests across 79 files, 0 failures** (10 new).

New frontend coverage:

- `PlayerDetail.test.tsx` — **previously had zero invitation coverage.** Now
  covers the owner seeing and using the button, the linked-profile explanation,
  each blocked reason, admin access, state restored after reload, revoke, and a
  surfaced failure.
- `Players.test.tsx` — the accountless recording mode sends the right payload.
- `Coaches.test.tsx` — the accountless mode is never offered for a coach.

## Known limitation

Email matching uses `Person#email`, which is free-text and nullable. A player who
signed up without an address cannot redeem an address-restricted invitation and
needs an open one. Signup does copy the account address onto the `Person`, so
this is uncommon, but it is a real gap rather than a solved problem.

## Migration

`20261005000001_add_invitee_email_to_player_claim_invitations`. Applied and
verified in the local development and test databases; it adds one column and one
partial unique index. Production rollout remains **blocked** for the reasons
recorded in `IDENTITY_PHASE_14_PRODUCTION_MIGRATION.md`, and this migration is
one more item for that runbook.