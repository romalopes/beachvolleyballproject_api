# A verified email may be invited to claim more than one distinct profile or
# Person. Uniqueness is per claimable subject (enforced by the existing partial
# index), not global across every invitation in the system.
class AllowMultipleActiveClaimInvitees < ActiveRecord::Migration[8.1]
  INDEX_NAME = "index_claim_invitations_one_active_per_email"

  def up
    remove_index :claim_invitations, name: INDEX_NAME, if_exists: true
  end

  def down
    # Reinstating this global restriction could make rollback impossible when
    # one verified recipient has active invitations to multiple claimables.
    # Refuse instead of deleting valid invitations or silently changing state.
    duplicates = select_value(<<~SQL).to_i
      SELECT COUNT(*) FROM (
        SELECT LOWER(BTRIM(invitee_email))
        FROM claim_invitations
        WHERE status = 'active' AND invitee_email IS NOT NULL
        GROUP BY LOWER(BTRIM(invitee_email))
        HAVING COUNT(*) > 1
      ) duplicate_recipients
    SQL
    raise "Cannot restore global active invitee uniqueness: #{duplicates} duplicate recipient groups exist" if duplicates.positive?

    add_index :claim_invitations, :invitee_email, unique: true,
              where: "status = 'active' AND invitee_email IS NOT NULL",
              name: INDEX_NAME
  end
end
