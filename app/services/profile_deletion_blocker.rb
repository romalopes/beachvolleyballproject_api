# Protected-reference checks and authorization for the issue's narrowly-scoped
# profile hard-delete capability. Associations are also restrictive in models.
class ProfileDeletionBlocker
  class Blocked < StandardError
    attr_reader :references

    def initialize(message, references: [])
      @references = references
      super(message)
    end
  end

  def self.blockers(profile)
    blockers = []
    person = profile.person
    # A profile is only disposable while its linked identity is still an
    # unclaimed, unused record. History can be attached to a sibling profile,
    # so check every profile for the Person as well as the target profile.
    if person
      blockers << "person_account" if person.account.present?
      person.player_profiles.each do |player|
        blockers << "person_training_session_participants" if player.training_session_participants.exists?
        blockers << "person_assessment_session_participants" if player.assessment_session_participants.exists?
        blockers << "person_assessments" if player.assessments.exists?
      end
      person.coach_profiles.each do |coach|
        blockers << "person_assessments" if coach.assessments.exists?
        blockers << "person_assessment_sessions" if coach.assessment_sessions.exists?
      end
    end
    if profile.is_a?(PlayerProfile)
      blockers << "assessments" if profile.assessments.exists?
      blockers << "training_session_participants" if profile.training_session_participants.exists?
      blockers << "assessment_session_participants" if profile.assessment_session_participants.exists?
      blockers << "player_coaches" if profile.player_coaches.exists?
      blockers << "ranking_consolidation_rows" if profile.ranking_consolidation_rows.exists?
      blockers << "ranking_snapshots" if RankingConsolidationSession.where("ranking_snapshot @> ?::jsonb", [ { player_profile_id: profile.id } ].to_json).exists?
      blockers << "player_claims" if PlayerClaim.where(claimable: profile).or(PlayerClaim.where(player_profile_id: profile.id)).exists?
      blockers << "claim_invitations" if ClaimInvitation.where(claimable: profile).exists?
      blockers << "legacy_invitations" if PlayerClaimInvitation.exists?(player_profile_id: profile.id)
    else
      blockers << "assessments" if profile.assessments.exists?
      blockers << "assessment_sessions" if profile.assessment_sessions.exists?
      blockers << "player_coaches" if profile.player_coaches.exists?
      blockers << "player_claims" if PlayerClaim.where(claimable: profile).exists?
      blockers << "claim_invitations" if ClaimInvitation.where(claimable: profile).exists?
    end
    blockers << "profile_merge_audit" if ProfileMerge.where(source_profile: profile).or(ProfileMerge.where(canonical_profile: profile)).exists?
    blockers << "profile_merge_links" if profile.merged? || profile.merged_profiles.exists?
    blockers.uniq
  end

  def self.authorized?(profile:, user:)
    return true if user&.admin?
    false
  end

  def self.destroy!(profile:, user:)
    profile.class.transaction do
      profile.with_lock do
        raise Blocked, "Forbidden" unless authorized?(profile: profile, user: user)

        references = blockers(profile)
        raise Blocked.new("Profile has protected history", references: references) if references.any?

        profile.destroy!
      end
    end
  rescue ActiveRecord::InvalidForeignKey
    raise Blocked.new("A protected reference was added concurrently; profile was not deleted", references: blockers(profile))
  end
end
