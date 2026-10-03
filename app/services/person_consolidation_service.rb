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

  def self.execute!(source_person:, canonical_person:, performed_by:)
    new(source_person, canonical_person).execute!(performed_by: performed_by)
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

  def execute!(performed_by:)
    result = nil
    Person.transaction do
      [@source.id, @canonical.id].sort.each { |id| Person.lock.find(id) }
      @source.reload
      @canonical.reload
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
                                          performed_by: performed_by, result: counts.merge(merged_people: merged_from_count),
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
        conflicts << { type: type.to_s, container_id: container_id,
                       source_record_id: left[container_id], canonical_record_id: right[container_id] }
      end
    end
    conflicts
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
