require "test_helper"

class PersonConsolidationServiceTest < ActiveSupport::TestCase
  test "preview is read only and reports records to reassign" do
    source = people(:accountless_player)
    canonical = create_person("Canonical Preview")

    preview = PersonConsolidationService.preview(source_person: source, canonical_person: canonical)

    assert preview[:ready]
    assert_equal 1, preview[:records_to_reassign][:player_profiles]
    assert_equal 1, preview[:records_to_reassign][:organisation_memberships]
    assert_equal source.id, player_profiles(:pedro_player).reload.person_id
    assert_equal "active", source.reload.status
  end

  test "consolidation moves existing records and retains source and audit provenance" do
    source = people(:accountless_player)
    canonical = create_person("Canonical Destination")
    profile_id = player_profiles(:pedro_player).id
    membership_id = organisation_memberships(:accountless_club_member).id
    alias_record = source.person_aliases.create!(full_name: "Pedro Santos Jr", alias_type: "nickname")
    formerly_merged = Person.create!(first_name: "Older", last_name: "Duplicate", status: "merged",
                                     merged_into: source, creation_source: "system")
    actor = users(:two)

    audit = PersonConsolidationService.execute!(source_person: source, canonical_person: canonical, performed_by: actor)

    assert_equal canonical.id, PlayerProfile.find(profile_id).person_id
    assert_equal canonical.id, OrganisationMembership.find(membership_id).person_id
    assert_equal canonical.id, PersonAlias.find(alias_record.id).person_id
    assert_equal "merged", source.reload.status
    assert_equal canonical.id, source.merged_into_id
    assert_equal canonical.id, formerly_merged.reload.merged_into_id
    assert_equal actor.id, source.merged_by_id
    assert_not_nil source.merged_at
    assert_equal source.id, audit.source_person_id
    assert_equal canonical.id, audit.canonical_person_id
    assert_equal actor.id, audit.performed_by_id
    assert_equal 1, audit.result.fetch("player_profiles")
  end

  test "source-only account is transferred to canonical person" do
    source = people(:one)
    canonical = create_person("Account Destination")
    account_id = accounts(:one).id

    PersonConsolidationService.execute!(source_person: source, canonical_person: canonical, performed_by: users(:two))

    assert_equal canonical.id, Account.find(account_id).person_id
  end

  test "canonical-only account remains attached to canonical person" do
    source = create_person("Accountless Source")
    canonical = people(:two)
    account_id = accounts(:two).id

    PersonConsolidationService.execute!(source_person: source, canonical_person: canonical, performed_by: users(:two))

    assert_equal canonical.id, Account.find(account_id).person_id
  end

  test "multiple player and coach profiles are retained as distinct records" do
    source = people(:accountless_player)
    canonical = create_person("Profiles Canonical")
    target_player = PlayerProfile.create!(person: canonical, status: "active", preferred_position: "blocker")
    source_coach = CoachProfile.create!(person: source, status: "active", coaching_level: "level_1")
    target_coach = CoachProfile.create!(person: canonical, status: "active", coaching_level: "level_2")

    PersonConsolidationService.execute!(source_person: source, canonical_person: canonical, performed_by: users(:two))

    assert_equal [player_profiles(:pedro_player).id, target_player.id].sort,
                 PlayerProfile.where(person_id: canonical.id).pluck(:id).sort
    assert_equal [source_coach.id, target_coach.id].sort,
                 CoachProfile.where(person_id: canonical.id).pluck(:id).sort
  end

  test "audit failure rolls every reassignment back" do
    source = people(:accountless_player)
    canonical = create_person("Rollback Destination")
    profile_id = player_profiles(:pedro_player).id

    assert_raises(ActiveRecord::RecordInvalid) do
      PersonConsolidationService.execute!(source_person: source, canonical_person: canonical, performed_by: nil)
    end

    assert_equal source.id, PlayerProfile.find(profile_id).person_id
    assert_equal "active", source.reload.status
    assert_empty PersonConsolidation.where(source_person_id: source.id)
  end

  test "two accounts and duplicate memberships are reported and block all writes" do
    source = people(:one)
    canonical = people(:two)

    error = assert_raises(PersonConsolidationService::Conflict) do
      PersonConsolidationService.execute!(source_person: source, canonical_person: canonical, performed_by: users(:two))
    end

    types = error.preview[:conflicts].map { |item| item[:type] }
    assert_includes types, "account_conflict"
    assert_includes types, "organisation_membership_conflict"
    assert_equal "active", source.reload.status
    assert_equal source.id, accounts(:one).reload.person_id
    assert_empty PersonConsolidation.where(source_person_id: source.id)
  end

  test "duplicate group membership blocks consolidation" do
    source = people(:accountless_player)
    canonical = people(:one)
    GroupMembership.create!(group: groups(:u19_squad), person: canonical, role: "member", status: "active")

    preview = PersonConsolidationService.preview(source_person: source, canonical_person: canonical)

    assert_not preview[:ready]
    assert_includes preview[:conflicts].map { |item| item[:type] }, "group_membership_conflict"
    assert_equal "active", source.reload.status
  end

  test "explicit membership resolution keeps the selected rows and audits discarded snapshots" do
    source = people(:accountless_player)
    canonical = create_person("Membership Canonical")
    organisation = organisations(:sydney_club)
    group = groups(:u19_squad)
    canonical_org = OrganisationMembership.create!(organisation: organisation, person: canonical,
                                                    role: "member", status: "active")
    canonical_group = GroupMembership.create!(group: group, person: canonical, role: "member", status: "active")
    preview = PersonConsolidationService.preview(source_person: source, canonical_person: canonical)
    resolutions = preview[:conflicts].map do |conflict|
      { type: conflict[:type], container_id: conflict[:container_id],
        keep_record_id: conflict[:source_record_id], reason: "Source record verified against club roster" }
    end

    audit = PersonConsolidationService.execute!(source_person: source, canonical_person: canonical,
                                                 performed_by: users(:two), membership_resolutions: resolutions)

    assert_equal canonical.id, organisation_memberships(:accountless_club_member).reload.person_id
    assert_not OrganisationMembership.exists?(id: canonical_org.id)
    assert_equal canonical.id, group_memberships(:u19_squad_pedro).reload.person_id
    assert_not GroupMembership.exists?(id: canonical_group.id)
    assert_equal 2, audit.result.fetch("membership_resolutions").length
    discarded_ids = audit.result.fetch("membership_resolutions").map { |item| item.fetch("discarded_record_id") }
    assert_equal [canonical_org.id, canonical_group.id].sort, discarded_ids.sort
    assert audit.result.fetch("membership_resolutions").all? { |item| item["discarded_record_snapshot"].present? && item["reason"].present? }
  end

  test "two-account conflict blocks in either source direction" do
    [[people(:one), people(:two)], [people(:two), people(:one)]].each do |source, canonical|
      error = assert_raises(PersonConsolidationService::Conflict) do
        PersonConsolidationService.execute!(source_person: source, canonical_person: canonical, performed_by: users(:two))
      end
      assert_includes error.preview[:conflicts].map { |item| item[:type] }, "account_conflict"
      assert_equal "active", source.reload.status
      assert_empty PersonConsolidation.where(source_person_id: source.id)
    end
  end

  test "rejects self consolidation, merged sources, merged targets, and replay" do
    canonical = create_person("Canonical Guard")
    assert_raises(PersonConsolidationService::InvalidConsolidation) do
      PersonConsolidationService.preview(source_person: canonical, canonical_person: canonical)
    end

    assert_raises(PersonConsolidationService::InvalidConsolidation) do
      PersonConsolidationService.preview(source_person: people(:merged), canonical_person: canonical)
    end
    assert_raises(PersonConsolidationService::InvalidConsolidation) do
      PersonConsolidationService.preview(source_person: people(:accountless_player), canonical_person: people(:merged))
    end

    PersonConsolidationService.execute!(source_person: people(:accountless_player), canonical_person: canonical, performed_by: users(:two))
    assert_raises(PersonConsolidationService::InvalidConsolidation) do
      PersonConsolidationService.execute!(source_person: people(:accountless_player), canonical_person: canonical, performed_by: users(:two))
    end
  end

  private

  def create_person(name)
    first, last = name.split(" ", 2)
    Person.create!(first_name: first, last_name: last, creation_source: "system")
  end
end
