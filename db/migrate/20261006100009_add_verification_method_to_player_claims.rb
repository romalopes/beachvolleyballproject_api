class AddVerificationMethodToPlayerClaims < ActiveRecord::Migration[8.1]
  def change
    add_column :player_claims, :verification_method, :string
    add_check_constraint :player_claims,
                         "verification_method IS NULL OR verification_method IN ('staff_confirmed', 'government_id', 'in_person', 'other')",
                         name: "player_claims_valid_verification_method"
  end
end
