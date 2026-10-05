class PlayerClaimService
  class ClaimError < StandardError; end

  def self.request!(person:, initiated_by_person:, claimable: nil, player_profile: nil)
    profile = claimable || player_profile
    raise ClaimError, "Profile cannot be claimed" unless profile.is_a?(PlayerProfile) || profile.is_a?(CoachProfile)

    PlayerClaim.transaction do
      profile.with_lock do
        subject = ClaimSubject.for(profile)
        raise ClaimError, "Profile cannot be claimed" unless subject.eligible?
        raise ClaimError, "Profile needs a display name before it can be claimed" if profile.full_name.blank?
        if PlayerClaim.pending.where(claimable: profile).exists?
          raise ClaimError, "A pending claim already exists for this profile"
        end
        raise ClaimError, "Person cannot submit a claim" unless person&.status == "active"

        PlayerClaim.create!(
          claimable: profile,
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
        # `subject`, not `player_profile`: after the Phase 18 migration every
        # claim stores its subject polymorphically and leaves
        # `player_profile_id` NULL, so the legacy association is nil.
        subject = ClaimSubject.for(claim.subject)
        claim.subject.with_lock do
          raise ClaimError, "The profile cannot be claimed" unless subject.eligible? && subject.still_unclaimed?

          subject.effect!(claimant_person: claim.person, actor: reviewer)
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
