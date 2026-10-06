class PlayerClaimService
  class ClaimError < StandardError; end

  def self.request!(account: nil, claimable: nil, player_profile: nil)
    profile = claimable || player_profile
    raise ClaimError, "Profile cannot be claimed" unless profile.is_a?(PlayerProfile) || profile.is_a?(CoachProfile)
    raise ClaimError, "An account is required to request a claim" unless account

    PlayerClaim.transaction do
      profile.with_lock do
        subject = ClaimSubject.for(profile)
        raise ClaimError, "Profile cannot be claimed" unless subject.eligible?
        raise ClaimError, "Profile needs a display name before it can be claimed" if profile.full_name.blank?
        if PlayerClaim.pending.where(claimable: profile, claimant_account: account).exists?
          raise ClaimError, "Your account already has a pending claim for this profile"
        end

        PlayerClaim.create!(
          claimable: profile,
          claimant_account: account,
          initiated_by_account: account,
          status: "pending"
        )
      end
    end
  end

  def self.approve!(claim:, reviewer_account: nil, reviewer: nil, verification_method:)
    reviewer_account ||= account_for_reviewer(reviewer)
    raise ClaimError, "An authorized reviewer Account is required" unless reviewer_account
    raise ClaimError, "Choose how the claimant's identity was verified" unless PlayerClaim::VERIFICATION_METHODS.include?(verification_method.to_s)

    competing_claims = []
    PlayerClaim.transaction do
      profile = claim.subject
      raise ClaimError, "The profile cannot be claimed" unless profile.is_a?(PlayerProfile) || profile.is_a?(CoachProfile)

      profile.with_lock do
        locked_claims = PlayerClaim.where(claimable: profile).order(:id).lock.to_a
        locked_claim = locked_claims.find { |row| row.id == claim.id }
        raise ClaimError, "Claim is no longer pending" unless locked_claim&.pending?

        subject = ClaimSubject.for(profile)
        claimant_account = locked_claim.claimant_account
        raise ClaimError, "The claimant Account is no longer available" unless claimant_account
        unless ProfilePolicy.new(actor: reviewer_account.user, profile: profile).review_claim?
          raise ClaimError, "Forbidden"
        end
        if reviewer_account.id == claimant_account.id
          raise ClaimError, "A claimant cannot review their own claim"
        end
        unless profile.account_id.nil? && subject.eligible? && subject.still_unclaimed? &&
               ProfileClaimability.allowed?(profile: profile, user: claimant_account.user)
          raise ClaimError, "The profile is no longer eligible for this claim"
        end

        now = Time.current
        subject.effect!(claimant_account: claimant_account, actor: reviewer_account.user)
        locked_claim.update!(
          status: "approved",
          reviewed_by_account: reviewer_account,
          reviewed_at: now,
          verification_method: verification_method
        )
        competing_claims = locked_claims.reject { |row| row.id == locked_claim.id }
                                         .select(&:pending?)
        competing_claims.each do |other_claim|
          other_claim.update!(
            status: "rejected",
            reviewed_by_account: reviewer_account,
            reviewed_at: now,
            rejection_reason: "Another claim for this profile was approved"
          )
        end
        claim = locked_claim
      end
    end
    notify_decision!(claim)
    competing_claims.each { |other_claim| notify_decision!(other_claim) }
    claim
  end

  def self.reject!(claim:, reviewer_account: nil, reviewer: nil, reason: nil)
    reviewer_account ||= account_for_reviewer(reviewer)
    raise ClaimError, "An authorized reviewer Account is required" unless reviewer_account
    raise ClaimError, "Forbidden" unless ProfilePolicy.new(actor: reviewer_account.user, profile: claim.subject).review_claim?
    claimant_account = claim.claimant_account
    raise ClaimError, "A claimant cannot review their own claim" if claimant_account&.id == reviewer_account.id

    PlayerClaim.transaction do
      claim.with_lock do
        ensure_pending!(claim)
        claim.update!(status: "rejected", reviewed_by_account: reviewer_account,
                      reviewed_at: Time.current, rejection_reason: reason)
      end
    end
    notify_decision!(claim)
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

  def self.account_for_reviewer(reviewer)
    case reviewer
    when Account then reviewer
    when User then reviewer.account
    end
  end
  private_class_method :account_for_reviewer

  def self.notify_decision!(claim)
    account = claim.claimant_account
    return unless account&.user&.email_address.present?

    ProfileClaimsMailer.decision(claim).deliver_later
  rescue StandardError => error
    Rails.logger.error("Claim decision notification failed for claim #{claim.id}: #{error.message}")
  end
  private_class_method :notify_decision!
end
