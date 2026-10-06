# Canonical eligibility for discovering/requesting an unlinked profile.
#
# Candidate search exposes only active, unlinked profiles that are already
# visible to the signed-in user. A selected profile still creates a pending
# claim; staff approval, rather than organisation or coaching membership, is
# the safeguard against an incorrect self-claim.
class ProfileClaimability
  PROFILE_TYPES = %w[PlayerProfile CoachProfile].freeze

  def self.profiles_for(user:, type: "PlayerProfile")
    return PlayerProfile.none unless PROFILE_TYPES.include?(type)

    profile_class = type.constantize
    return profile_class.none unless user

    # Claim suggestions must obey the same visibility boundary as profile
    # catalogues and detail endpoints. Organization or coaching relationships
    # alone must not expose a profile its owner marked private.
    base = profile_class.active.where(account_id: nil).visible_to(user)
    return profile_class.none unless user.account

    base
  end

  def self.allowed?(profile:, user:)
    return false unless profile && PROFILE_TYPES.include?(profile.class.name)

    profiles_for(user: user, type: profile.class.name).where(id: profile.id).exists?
  end
end
