# Profiles available to staff workflows which must be narrower than a global
# catalogue view. Administrators and the existing global curator role retain
# their oversight scope; coaches only see the profiles they recorded for
# management actions. The data model has no organisation-specific curator grant.
class ProfileManagementScope
  def self.scope(relation, user:)
    return relation.none unless user
    return relation if user.admin? || user.curator?
    return relation.owned_by(user) if user.coach? && !user.curator?
    relation.none
  end

  def self.allowed?(profile:, user:)
    return false unless profile && %w[PlayerProfile CoachProfile].include?(profile.class.name)

    scope(profile.class.all, user: user).where(id: profile.id).exists?
  end
end
