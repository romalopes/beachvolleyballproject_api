# Transactional merge of two duplicate profiles of the same kind. The source
# row is retained and archived; domain references keep their IDs wherever a
# historical JSON snapshot embeds them.
class ProfileMergeService
  class Error < StandardError; end

  PROFILE_CLASSES = [ PlayerProfile, CoachProfile ].freeze

  def self.merge!(source:, canonical:, actor:, reason:)
    new(source, canonical, actor, reason).merge!
  end

  def initialize(source, canonical, actor, reason)
    @source = source
    @canonical = canonical
    @actor = actor
    @reason = reason.to_s.strip
  end

  def merge!
    raise Error, "Only an administrator or curator can merge profiles" unless ProfilePolicy.new(actor: @actor, profile: @source).merge?
    raise Error, "A reason is required" if @reason.blank?
    raise Error, "Profiles must be the same type" unless @source.class == @canonical.class && PROFILE_CLASSES.include?(@source.class)

    result = nil
    @source.class.transaction do
      [ @source.id, @canonical.id ].sort.each { |id| @source.class.lock.find(id) }
      @source.reload
      @canonical.reload
      validate_current_state!
      conflicts = unique_reference_conflicts
      raise Error, "Merge blocked by conflicting references: #{conflicts.join(', ')}" if conflicts.any?

      account = ProfileOwnership.account_for(@actor)
      revoke_open_invitations!
      counts = move_references!
      now = Time.current
      @source.update!(status: "archived", archived_at: now,
                      merged_into_profile_id: @canonical.id, merged_at: now,
                      merged_by_account: account)
      result = ProfileMerge.create!(source_profile: @source, canonical_profile: @canonical,
                                    merged_by_account: account, reason: @reason,
                                    reference_counts: counts)
    end
    result
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
    raise Error, "Profile merge could not be completed: #{e.message}"
  end

  private

  def validate_current_state!
    raise Error, "Profiles must be different records" if @source.id == @canonical.id
    raise Error, "Only active profiles can be merged" unless @source.status == "active" && @canonical.status == "active"
    source_account_id = @source.account_id || @source.person&.account_id
    canonical_account_id = @canonical.account_id || @canonical.person&.account_id
    unless source_account_id == canonical_account_id
      raise Error, "Profiles linked to different Accounts cannot be merged"
    end
    raise Error, "Source profile has already been merged" if @source.merged_into_profile_id.present? || ProfileMerge.exists?(source_profile: @source)
    raise Error, "Canonical profile is already merged" if @canonical.merged_into_profile_id.present?
    if PlayerClaim.pending.where(claimable: @source).exists? || PlayerClaim.pending.where(claimable: @canonical).exists?
      raise Error, "Resolve pending claims on both profiles before merging"
    end
  end

  def unique_reference_conflicts
    @source.is_a?(PlayerProfile) ? player_conflicts : coach_conflicts
  end

  def player_conflicts
    conflicts = []
    conflicts << "training_session_participants" if duplicate_rows?(TrainingSessionParticipant, :training_session_id)
    conflicts << "assessment_session_participants" if duplicate_rows?(AssessmentSessionParticipant, :assessment_session_id)
    conflicts << "ranking_consolidation_rows" if duplicate_rows?(RankingConsolidationRow, :ranking_consolidation_id)
    conflicts << "player_coaches" if overlapping_player_coach_periods?(source_column: :player_profile_id,
                                                                        canonical_column: :player_profile_id,
                                                                        counterpart_column: :coach_profile_id)
    conflicts
  end

  def coach_conflicts
    conflicts = []
    conflicts << "player_coaches" if overlapping_player_coach_periods?(source_column: :coach_profile_id,
                                                                        canonical_column: :coach_profile_id,
                                                                        counterpart_column: :player_profile_id)
    conflicts
  end

  # A merge may safely combine two non-overlapping historical periods for the
  # same pair. Any inclusive date overlap would make the resulting history
  # invalid, even when the start dates differ and both periods are ended.
  def overlapping_player_coach_periods?(source_column:, canonical_column:, counterpart_column:)
    PlayerCoach.where(source_column => @source.id)
               .joins("INNER JOIN player_coaches canonical_rows ON canonical_rows.#{counterpart_column} = player_coaches.#{counterpart_column}")
               .where(canonical_rows: { canonical_column => @canonical.id })
               .where("(player_coaches.end_date IS NULL OR canonical_rows.start_date <= player_coaches.end_date) " \
                      "AND (canonical_rows.end_date IS NULL OR player_coaches.start_date <= canonical_rows.end_date)")
               .exists?
  end

  def duplicate_rows?(model, container_column)
    model.where(player_profile_id: @source.id)
         .where(container_column => model.where(player_profile_id: @canonical.id).select(container_column))
         .exists?
  end

  def revoke_open_invitations!
    ClaimInvitation.where(claimable: @source, status: "active").find_each do |invitation|
      invitation.update!(status: invitation.expires_at <= Time.current ? "expired" : "revoked",
                         revoked_at: invitation.expires_at <= Time.current ? nil : Time.current)
    end
    if @source.is_a?(PlayerProfile)
      PlayerClaimInvitation.where(player_profile_id: @source.id, status: "active").find_each do |invitation|
        invitation.update!(status: invitation.expires_at <= Time.current ? "expired" : "revoked",
                           revoked_at: invitation.expires_at <= Time.current ? nil : Time.current)
      end
    end
  end

  def move_references!
    # This is intentionally an explicit list of profile foreign keys. Snapshot
    # JSON and person-owned memberships remain attached to the retained source
    # records so the merge never rewrites historical evidence indiscriminately.
    counts = {}
    if @source.is_a?(PlayerProfile)
      counts["assessments_as_player"] = Assessment.where(player_profile_id: @source.id).update_all(player_profile_id: @canonical.id)
      counts["training_session_participants"] = TrainingSessionParticipant.where(player_profile_id: @source.id).update_all(player_profile_id: @canonical.id)
      counts["assessment_session_participants"] = AssessmentSessionParticipant.where(player_profile_id: @source.id).update_all(player_profile_id: @canonical.id)
      counts["ranking_consolidation_rows"] = RankingConsolidationRow.where(player_profile_id: @source.id).update_all(player_profile_id: @canonical.id)
      counts["player_coaches"] = PlayerCoach.where(player_profile_id: @source.id).update_all(player_profile_id: @canonical.id)
    else
      counts["assessments_as_coach"] = Assessment.where(coach_profile_id: @source.id).update_all(coach_profile_id: @canonical.id)
      counts["assessment_sessions"] = AssessmentSession.where(coach_profile_id: @source.id).update_all(coach_profile_id: @canonical.id)
      counts["player_coaches"] = PlayerCoach.where(coach_profile_id: @source.id).update_all(coach_profile_id: @canonical.id)
    end
    counts
  end
end
