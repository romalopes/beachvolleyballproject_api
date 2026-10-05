# Repair the legacy backfill for databases that already ran
# BackfillClaimInvitations. The old migration copied only player invitations
# whose issuer Person had an Account and did not preserve used_by_id.
class ReconcileLegacyClaimInvitations < ActiveRecord::Migration[8.1]
  def up
    unresolved_issuers = select_value(<<~SQL).to_i
      SELECT COUNT(*)
      FROM player_claim_invitations pci
      LEFT JOIN people issuer ON issuer.id = pci.created_by_person_id
      LEFT JOIN accounts issuer_account ON issuer_account.person_id = issuer.id
      WHERE NOT EXISTS (
        SELECT 1 FROM claim_invitations ci WHERE ci.token_digest = pci.token_digest
      )
        AND COALESCE(issuer_account.user_id, issuer.created_by_id) IS NULL
    SQL
    raise "Cannot reconcile #{unresolved_issuers} player invitations: issuer Person has no linked or recorded User" if unresolved_issuers.positive?

    unresolved_claimants = select_value(<<~SQL).to_i
      SELECT COUNT(*)
      FROM player_claim_invitations pci
      LEFT JOIN accounts claimant_account ON claimant_account.person_id = pci.used_by_person_id
      WHERE pci.status = 'used'
        AND NOT EXISTS (
          SELECT 1 FROM claim_invitations ci
          WHERE ci.token_digest = pci.token_digest AND ci.used_by_id IS NOT NULL
        )
        AND claimant_account.user_id IS NULL
    SQL
    raise "Cannot reconcile #{unresolved_claimants} used player invitations: claimant Person has no linked User" if unresolved_claimants.positive?

    mismatched_tokens = select_value(<<~SQL).to_i
      SELECT COUNT(*)
      FROM player_claim_invitations pci
      JOIN claim_invitations ci ON ci.token_digest = pci.token_digest
      WHERE ci.claimable_type <> 'PlayerProfile' OR ci.claimable_id <> pci.player_profile_id
    SQL
    raise "Cannot reconcile #{mismatched_tokens} player invitations: token digest is assigned to a different claimable" if mismatched_tokens.positive?

    mismatched_person_tokens = select_value(<<~SQL).to_i
      SELECT COUNT(*)
      FROM person_account_invitations pai
      JOIN claim_invitations ci ON ci.token_digest = pai.token_digest
      WHERE ci.claimable_type <> 'Person' OR ci.claimable_id <> pai.person_id
    SQL
    raise "Cannot reconcile #{mismatched_person_tokens} Person invitations: token digest is assigned to a different claimable" if mismatched_person_tokens.positive?

    execute <<~SQL.squish
      UPDATE claim_invitations ci
      SET used_by_id = claimant_account.user_id
      FROM player_claim_invitations pci
      JOIN accounts claimant_account ON claimant_account.person_id = pci.used_by_person_id
      WHERE ci.token_digest = pci.token_digest
        AND ci.status = 'used'
        AND ci.used_by_id IS NULL
    SQL

    execute <<~SQL.squish
      INSERT INTO claim_invitations
        (claimable_type, claimable_id, invited_by_id, used_by_id, invitee_email,
         token_digest, status, expires_at, used_at, revoked_at, created_at, updated_at)
      SELECT 'PlayerProfile', pci.player_profile_id,
             COALESCE(issuer_account.user_id, issuer.created_by_id),
             claimant_account.user_id, pci.invitee_email, pci.token_digest,
             pci.status, pci.expires_at, pci.used_at, pci.revoked_at,
             pci.created_at, pci.updated_at
      FROM player_claim_invitations pci
      JOIN people issuer ON issuer.id = pci.created_by_person_id
      LEFT JOIN accounts issuer_account ON issuer_account.person_id = issuer.id
      LEFT JOIN accounts claimant_account ON claimant_account.person_id = pci.used_by_person_id
      WHERE NOT EXISTS (
        SELECT 1 FROM claim_invitations ci WHERE ci.token_digest = pci.token_digest
      )
    SQL

    execute <<~SQL.squish
      INSERT INTO claim_invitations
        (claimable_type, claimable_id, invited_by_id, used_by_id, invitee_email,
         token_digest, status, expires_at, used_at, revoked_at, created_at, updated_at)
      SELECT 'Person', pai.person_id, pai.invited_by_id, pai.used_by_id,
             pai.invitee_email, pai.token_digest, pai.status, pai.expires_at,
             pai.used_at, pai.revoked_at, pai.created_at, pai.updated_at
      FROM person_account_invitations pai
      WHERE NOT EXISTS (
        SELECT 1 FROM claim_invitations ci WHERE ci.token_digest = pai.token_digest
      )
    SQL
  end

  def down
    # Source invitation rows remain intact. Removing the repaired copies would
    # break token redemption for clients already using the unified endpoints.
  end
end
