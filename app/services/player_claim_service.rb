class PlayerClaimService
  class ClaimError < StandardError; end

  def self.request!(player_profile:, person:, initiated_by_person:)
    PlayerClaim.transaction do
      player_profile.with_lock do
        raise ClaimError, "Player profile cannot be claimed" unless player_profile.person_id.nil? && player_profile.status == "active"
        raise ClaimError, "Player profile needs a display name before it can be claimed" if player_profile.display_name.blank?
        raise ClaimError, "A pending claim already exists for this profile" if player_profile.player_claims.pending.exists?
        raise ClaimError, "Person cannot submit a claim" unless person&.status == "active"

        player_profile.player_claims.create!(
          person: person,
          initiated_by_person: initiated_by_person,
          status: "pending"
        )
      end
    end
  end

  def self.approve!(claim:, reviewer:)
    PlayerClaim.transaction do
      claim.with_lock do
        ensure_pending!(claim)
        profile = claim.player_profile
        profile.with_lock do
          raise ClaimError, "Player profile cannot be claimed" unless profile.person_id.nil? && profile.status == "active"

          profile.update!(person: claim.person)
          claim.update!(status: "approved", reviewed_by_person: reviewer, reviewed_at: Time.current)
        end
      end
    end
    claim
  end

  def self.reject!(claim:, reviewer:, reason:)
    PlayerClaim.transaction do
      claim.with_lock do
        ensure_pending!(claim)
        claim.update!(status: "rejected", reviewed_by_person: reviewer,
                      reviewed_at: Time.current, rejection_reason: reason)
      end
    end
    claim
  end

  def self.cancel!(claim:)
    PlayerClaim.transaction do
      claim.with_lock do
        ensure_pending!(claim)
        claim.update!(status: "cancelled")
      end
    end
    claim
  end

  def self.ensure_pending!(claim)
    raise ClaimError, "Claim is no longer pending" unless claim.pending?
  end
  private_class_method :ensure_pending!
end
