# Moves the two legacy invitation tables into the unified `claim_invitations`.
#
# The legacy tables are intentionally *kept* in this migration: the old models
# and endpoints stay available for one release so an existing client keeps
# working while the SPA is moved over. A later migration drops them.
#
# `emailed_at` is not recoverable from either legacy table (neither recorded it),
# so every backfilled row gets NULL — which means every pre-existing invitation
# requires staff review rather than auto-accepting. That is the fail-closed
# direction and is deliberate.
class BackfillClaimInvitations < ActiveRecord::Migration[8.1]
  def up
    # Player-profile invitations. `created_by_person_id` names a Person, so the
    # legacy issuer is resolved to the User that owns that Person's Account.
    execute <<~SQL.squish
      INSERT INTO claim_invitations
        (claimable_type, claimable_id, invited_by_id, invitee_email,
         token_digest, status, expires_at, used_at, revoked_at,
         created_at, updated_at)
      SELECT 'PlayerProfile', pci.player_profile_id, a.user_id, pci.invitee_email,
             pci.token_digest, pci.status, pci.expires_at, pci.used_at,
             pci.revoked_at, pci.created_at, pci.updated_at
      FROM player_claim_invitations pci
      JOIN people p ON p.id = pci.created_by_person_id
      JOIN accounts a ON a.person_id = p.id
      WHERE NOT EXISTS (
        SELECT 1 FROM claim_invitations ci
        WHERE ci.token_digest = pci.token_digest
      )
    SQL

    # Person account invitations already record the issuing User directly.
    execute <<~SQL.squish
      INSERT INTO claim_invitations
        (claimable_type, claimable_id, invited_by_id, invitee_email,
         token_digest, status, expires_at, used_at, revoked_at,
         created_at, updated_at)
      SELECT 'Person', pai.person_id, pai.invited_by_id, pai.invitee_email,
             pai.token_digest, pai.status, pai.expires_at, pai.used_at,
             pai.revoked_at, pai.created_at, pai.updated_at
      FROM person_account_invitations pai
      WHERE NOT EXISTS (
        SELECT 1 FROM claim_invitations ci
        WHERE ci.token_digest = pai.token_digest
      )
    SQL
  end

  def down
    # The legacy rows are still intact, so there is nothing to restore.
  end
end
