# One invitation table for every kind of identity claim.
#
# Two near-identical tables existed before this: `player_claim_invitations`
# (attaches an unlinked PlayerProfile to a Person) and
# `person_account_invitations` (attaches a login Account to an accountless
# Person). Same token digest, same expiry, same revoke-on-reissue, same
# one-active-per-subject rule — written twice, and disagreeing about who the
# issuer is (a Person vs a User). This collapses them into one polymorphic
# record so the subject decides the rules rather than the table.
#
# `claimable_type` / `claimable_id` is the subject:
#   * "PlayerProfile" - an unlinked profile adopts a Person
#   * "CoachProfile"  - an unlinked profile adopts a Person
#   * "Person"        - a login Account adopts this identity
#
# `emailed_at` is the security-critical column for the auto-accept rule: an
# invitation auto-accepts only when the club actually *emailed* it to the
# address the recipient controls. A link that was copied around by hand has a
# NULL `emailed_at` and always goes to staff review instead. Backfilled rows
# therefore get NULL and fall to review, which is the safe direction.
class CreateClaimInvitations < ActiveRecord::Migration[8.1]
  def change
    create_table :claim_invitations do |t|
      t.references :claimable, null: false, polymorphic: true
      t.references :invited_by, null: false, foreign_key: { to_table: :users }
      t.references :used_by, foreign_key: { to_table: :users }
      t.string :invitee_email
      t.datetime :emailed_at
      t.string :token_digest, null: false
      t.string :status, null: false, default: "active"
      t.datetime :expires_at, null: false
      t.datetime :used_at
      t.datetime :revoked_at
      t.timestamps
    end

    add_index :claim_invitations, :token_digest, unique: true
    add_index :claim_invitations, [ :claimable_type, :claimable_id ], unique: true,
              where: "status = 'active'", name: "index_claim_invitations_one_active_per_subject"
    add_index :claim_invitations, :invitee_email, unique: true,
              where: "status = 'active' AND invitee_email IS NOT NULL",
              name: "index_claim_invitations_one_active_per_email"
    add_check_constraint :claim_invitations,
                         "status IN ('active', 'used', 'revoked', 'expired')",
                         name: "claim_invitations_valid_status"
  end
end
