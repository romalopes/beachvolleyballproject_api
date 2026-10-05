# Restricts a claim invitation to a single email address.
#
# Until now an invitation was a pure bearer token: whoever held the link could
# redeem it. That is the right default when the club has no address for the
# player yet (a placeholder profile has no Person and therefore no email), but
# it is not enough when the coach does know who the player is.
#
# `invitee_email` is optional on purpose:
#   * NULL  — open invitation, today's behaviour, redeemable by any signed-in
#             Person. Required for placeholder profiles, which have no email.
#   * value — the redeeming Person's email must match, case-insensitively.
#
# The unique index is per (profile, email) rather than per profile: the existing
# "one active invitation per profile" index already limits how many live links a
# profile can have, and a club may legitimately invite the same person to
# several different profiles.
class AddInviteeEmailToPlayerClaimInvitations < ActiveRecord::Migration[8.1]
  def change
    add_column :player_claim_invitations, :invitee_email, :string

    add_index :player_claim_invitations, [ :player_profile_id, :invitee_email ],
              unique: true,
              where: "status = 'active' AND invitee_email IS NOT NULL",
              name: "index_player_claim_invitations_one_active_per_email"
  end
end
