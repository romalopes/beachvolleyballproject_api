# Shared archive behavior for PlayerProfile and CoachProfile. Archiving stops
# any outstanding claim link from being redeemed; restoring an ordinary
# archived profile permits a new invitation to be issued.
module ProfileArchiveLifecycle
  extend ActiveSupport::Concern

  included do
    before_validation :synchronize_archived_at
    after_update :revoke_open_claim_invitations, if: :saved_change_to_status?
  end

  private

  def synchronize_archived_at
    if status == "archived"
      self.archived_at ||= Time.current
    elsif merged_into_profile_id.blank?
      self.archived_at = nil
    end
  end

  def revoke_open_claim_invitations
    return unless status == "archived"

    now = Time.current
    invitations = ClaimInvitation.where(claimable: self, status: "active")
    invitations.where("expires_at <= ?", now).update_all(status: "expired", updated_at: now)
    invitations.where("expires_at > ?", now).update_all(status: "revoked", revoked_at: now, updated_at: now)

  end
end
