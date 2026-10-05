# Keep invitations for already-archived profiles consistent with the archive
# lifecycle. Redemption would reject these subjects regardless, but active
# statuses would mislead staff and leave needless bearer tokens live.
class RevokeArchivedProfileInvitations < ActiveRecord::Migration[8.1]
  def up
    revoke_unified_invitations
    revoke_legacy_player_invitations
  end

  def down
    # Revocation is one-way: restoring a profile must require a newly issued
    # invitation rather than reviving a token that may have been shared.
  end

  private

  def revoke_unified_invitations
    execute <<~SQL.squish
      UPDATE claim_invitations invitations
      SET status = CASE WHEN invitations.expires_at <= CURRENT_TIMESTAMP THEN 'expired' ELSE 'revoked' END,
          revoked_at = CASE WHEN invitations.expires_at <= CURRENT_TIMESTAMP THEN NULL ELSE CURRENT_TIMESTAMP END,
          updated_at = CURRENT_TIMESTAMP
      WHERE invitations.status = 'active'
        AND ((invitations.claimable_type = 'PlayerProfile' AND EXISTS (
          SELECT 1 FROM player_profiles profiles
          WHERE profiles.id = invitations.claimable_id AND profiles.status = 'archived'
        )) OR (invitations.claimable_type = 'CoachProfile' AND EXISTS (
          SELECT 1 FROM coach_profiles profiles
          WHERE profiles.id = invitations.claimable_id AND profiles.status = 'archived'
        )))
    SQL
  end

  def revoke_legacy_player_invitations
    execute <<~SQL.squish
      UPDATE player_claim_invitations invitations
      SET status = CASE WHEN invitations.expires_at <= CURRENT_TIMESTAMP THEN 'expired' ELSE 'revoked' END,
          revoked_at = CASE WHEN invitations.expires_at <= CURRENT_TIMESTAMP THEN NULL ELSE CURRENT_TIMESTAMP END,
          updated_at = CURRENT_TIMESTAMP
      FROM player_profiles profiles
      WHERE invitations.player_profile_id = profiles.id
        AND profiles.status = 'archived'
        AND invitations.status = 'active'
    SQL
  end
end
