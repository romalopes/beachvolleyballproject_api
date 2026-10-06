class AddDeclinedStateToClaimInvitations < ActiveRecord::Migration[8.1]
  def up
    add_column :claim_invitations, :declined_at, :datetime
    remove_check_constraint :claim_invitations, name: "claim_invitations_valid_status"
    add_check_constraint :claim_invitations,
      "status IN ('active', 'used', 'revoked', 'expired', 'declined')",
      name: "claim_invitations_valid_status"
  end

  def down
    remove_check_constraint :claim_invitations, name: "claim_invitations_valid_status"
    add_check_constraint :claim_invitations,
      "status IN ('active', 'used', 'revoked', 'expired')",
      name: "claim_invitations_valid_status"
    remove_column :claim_invitations, :declined_at
  end
end
