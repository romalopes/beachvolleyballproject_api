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
