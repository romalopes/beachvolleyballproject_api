# Canonical eligibility for discovering/requesting an unlinked profile.
#
# Scope is derived from existing domain links: the profile creator belongs to
# one of the claimant's active organisations, or a current PlayerCoach row joins
# the profile to one of the claimant's opposite-kind profiles. An issued
# invitation is a separate, explicit authorization and does not require the
# invitee to be discoverable through this search policy.
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

    organisation_ids = user.account.organisation_memberships.active.select(:organisation_id)
    organisation_people = Person.joins(:organisation_memberships)
                                .where(organisation_memberships: { organisation_id: organisation_ids, status: "active" })
                                .select(:id)
    creator_accounts = Account.where(id: OrganisationMembership.where(organisation_id: organisation_ids, status: "active").select(:account_id))
    creator_users = creator_accounts.select(:user_id)
    same_organisation = base.where(created_by_account_id: creator_accounts)
                             .or(base.where(created_by_id: creator_users))

    same_coach = if type == "PlayerProfile"
      base.where(id: PlayerCoach.current.where(coach_profile_id: user.account.coach_profiles.select(:id)).select(:player_profile_id))
    else
      base.where(id: PlayerCoach.current.where(player_profile_id: user.account.player_profiles.select(:id)).select(:coach_profile_id))
    end

    same_organisation.or(same_coach)
  end

  def self.allowed?(profile:, user:)
    return false unless profile && PROFILE_TYPES.include?(profile.class.name)

    profiles_for(user: user, type: profile.class.name).where(id: profile.id).exists?
  end
end
