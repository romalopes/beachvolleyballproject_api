class PersonConsolidationService
  class Error < StandardError; end
  class InvalidConsolidation < Error; end
  class Conflict < Error
    attr_reader :preview

    def initialize(preview)
      @preview = preview
      super("Person consolidation has unresolved conflicts")
    end
  end

  RELATIONSHIPS = {
    player_profiles: PlayerProfile,
    coach_profiles: CoachProfile,
    organisation_memberships: OrganisationMembership,
    group_memberships: GroupMembership,
    person_aliases: PersonAlias
  }.freeze

  def self.preview(source_person:, canonical_person:)
    new(source_person, canonical_person).preview
  end

  def self.execute!(source_person:, canonical_person:, performed_by:, membership_resolutions: [])
    new(source_person, canonical_person).execute!(performed_by: performed_by,
                                                  membership_resolutions: membership_resolutions)
  end

  def initialize(source_person, canonical_person)
    @source = source_person
    @canonical = canonical_person
  end

  def preview
    validate_people!
    conflicts = conflict_list
    {
      source_person: person_summary(@source),
      canonical_person: person_summary(@canonical),
      conflicts: conflicts,
      ready: conflicts.empty?,
      records_to_reassign: record_counts
    }
  end

  def execute!(performed_by:, membership_resolutions: [])
    result = nil
    Person.transaction do
      [@source.id, @canonical.id].sort.each { |id| Person.lock.find(id) }
      @source.reload
      @canonical.reload
      current_preview = preview
      resolved_memberships = resolve_membership_conflicts!(
        current_preview[:conflicts], membership_resolutions
      )
      current_preview = preview
      raise Conflict, current_preview unless current_preview[:ready]
      if PersonConsolidation.exists?(source_person_id: @source.id)
        raise InvalidConsolidation, "Source person has already been consolidated"
      end

      now = Time.current
      counts = current_preview[:records_to_reassign]
      RELATIONSHIPS.each do |_name, model|
        model.where(person_id: @source.id).update_all(person_id: @canonical.id, updated_at: now)
      end
      Account.where(person_id: @source.id).update_all(person_id: @canonical.id, updated_at: now) if @source.account
      # Flatten existing merge references so every merged record points directly
      # to the canonical identity and cannot form a chain through this source.
      merged_from_count = Person.where(merged_into_id: @source.id).where.not(id: @source.id).update_all(merged_into_id: @canonical.id, updated_at: now)
      @source.update!(status: "merged", merged_into: @canonical, merged_by: performed_by, merged_at: now)
      audit = PersonConsolidation.create!(source_person: @source, canonical_person: @canonical,
                                          performed_by: performed_by,
                                          result: counts.merge(merged_people: merged_from_count,
                                                               membership_resolutions: resolved_memberships),
                                          completed_at: now)
      result = audit
    end
    result
  end

  private

  def validate_people!
    raise ActiveRecord::RecordNotFound unless @source&.persisted? && @canonical&.persisted?
    raise InvalidConsolidation, "Source and canonical people must be different" if @source.id == @canonical.id
    raise InvalidConsolidation, "Source person is already merged" if @source.status == "merged"
    raise InvalidConsolidation, "Canonical person must not be merged" if @canonical.status == "merged"
    raise InvalidConsolidation, "Source person has already been consolidated" if PersonConsolidation.exists?(source_person_id: @source.id)
    raise InvalidConsolidation, "Consolidation would create a merge cycle" if @canonical.merged_from.exists?(id: @source.id)
  end

  def conflict_list
    conflicts = []
    if @source.account && @canonical.account
      conflicts << { type: "account_conflict", source_record_id: @source.account.id, canonical_record_id: @canonical.account.id }
    end
    {
      organisation_membership_conflict: [OrganisationMembership, :organisation_id],
      group_membership_conflict: [GroupMembership, :group_id]
    }.each do |type, (model, key)|
      left = model.where(person_id: @source.id).pluck(:id, key).to_h.invert
      right = model.where(person_id: @canonical.id).pluck(:id, key).to_h.invert
      (left.keys & right.keys).each do |container_id|
        source_membership = model.find(left[container_id])
        canonical_membership = model.find(right[container_id])
        conflicts << { type: type.to_s, container_id: container_id,
                       source_record_id: left[container_id], canonical_record_id: right[container_id],
                       source_membership: membership_summary(source_membership),
                       canonical_membership: membership_summary(canonical_membership) }
      end
    end
    conflicts
  end

  def resolve_membership_conflicts!(conflicts, resolutions)
    return [] if resolutions.blank?

    unresolved_account_conflict = conflicts.any? { |conflict| conflict[:type] == "account_conflict" }
    raise Conflict, { source_person: person_summary(@source), canonical_person: person_summary(@canonical),
                      conflicts: conflicts, ready: false, records_to_reassign: record_counts } if unresolved_account_conflict

    membership_conflicts = conflicts.select { |conflict| membership_model_for(conflict[:type]) }
    decisions = Array(resolutions).map do |item|
      attributes = item.respond_to?(:to_unsafe_h) ? item.to_unsafe_h : item.to_h
      attributes.symbolize_keys
    end
    keys = decisions.map { |decision| [decision[:type].to_s, decision[:container_id].to_i] }
    expected_keys = membership_conflicts.map { |conflict| [conflict[:type], conflict[:container_id]] }
    unless keys.uniq.length == keys.length && keys.sort == expected_keys.sort
      raise Conflict, { source_person: person_summary(@source), canonical_person: person_summary(@canonical),
                        conflicts: conflicts, ready: false, records_to_reassign: record_counts }
    end

    membership_conflicts.map do |conflict|
      decision = decisions.find do |item|
        item[:type].to_s == conflict[:type] && item[:container_id].to_i == conflict[:container_id]
      end
      reason = decision[:reason].to_s.strip
      keep_id = decision[:keep_record_id].to_i
      source_id = conflict[:source_record_id]
      canonical_id = conflict[:canonical_record_id]
      unless reason.present? && [source_id, canonical_id].include?(keep_id)
        raise InvalidConsolidation, "Each membership resolution needs a valid keep_record_id and reason"
      end
      raise InvalidConsolidation, "Membership resolution reason must be 500 characters or fewer" if reason.length > 500

      model = membership_model_for(conflict[:type])
      discarded_id = keep_id == source_id ? canonical_id : source_id
      discarded = model.lock.find(discarded_id)
      snapshot = discarded.attributes
      discarded.destroy!
      model.where(id: keep_id, person_id: @source.id).update_all(person_id: @canonical.id, updated_at: Time.current) if keep_id == source_id
      {
        type: conflict[:type],
        container_id: conflict[:container_id],
        kept_record_id: keep_id,
        discarded_record_id: discarded_id,
        discarded_record_snapshot: snapshot,
        reason: reason
      }
    end
  end

  def membership_model_for(type)
    {
      "organisation_membership_conflict" => OrganisationMembership,
      "group_membership_conflict" => GroupMembership
    }[type.to_s]
  end

  def membership_summary(membership)
    membership.attributes.slice("id", "person_id", "role", "status", "joined_at", "left_at", "created_at", "updated_at")
  end

  def record_counts
    counts = RELATIONSHIPS.transform_values { |model| model.where(person_id: @source.id).count }
    counts[:accounts] = Account.where(person_id: @source.id).count
    counts[:merged_people] = Person.where(merged_into_id: @source.id).where.not(id: @source.id).count
    counts
  end

  def person_summary(person)
    { id: person.id, full_name: person.full_name, status: person.status }
  end
end
