require "test_helper"

class IdentityOrganisationGroupCompatibilityTest < ActiveSupport::TestCase
  test "player and coach identity keeps independent profiles and memberships through consolidation" do
    source = Person.create!(first_name: "Context", last_name: "Source", creation_source: "system")
    canonical = people(:two)

    source_player = PlayerProfile.create!(person: source, status: "active", preferred_position: "blocker")
    canonical_player = PlayerProfile.create!(person: canonical, status: "active", preferred_position: "setter")
    source_coaches = [
      CoachProfile.create!(person: source, status: "active", coaching_level: "level_1"),
      CoachProfile.create!(person: source, status: "active", coaching_level: "level_2")
    ]

    northern_membership = OrganisationMembership.create!(
      organisation: organisations(:northern_club), person: source, role: "member", status: "active"
    )
    national_membership = OrganisationMembership.create!(
      organisation: organisations(:volleyball_australia), person: source, role: "coach", status: "active"
    )
    linked_group = Group.create!(
      name: "Northern Context #{SecureRandom.hex(3)}",
      organisation: organisations(:northern_club),
      created_by: users(:two)
    )
    linked_membership = linked_group.group_memberships.create!(person: source, role: "member", status: "active")
    independent_group = Group.create!(name: "Independent Context #{SecureRandom.hex(3)}", created_by: users(:two))
    independent_membership = independent_group.group_memberships.create!(person: source, role: "member", status: "active")

    assert_equal [organisations(:northern_club).id, organisations(:volleyball_australia).id].sort,
                 source.active_organisation_ids.sort
    assert_nil independent_group.organisation_id
    assert linked_group.shares_organisation?([source.id])
    assert_equal 2, source.coach_profiles.count

    audit = PersonConsolidationService.execute!(source_person: source, canonical_person: canonical,
                                                 performed_by: users(:two))

    assert_equal canonical.id, PlayerProfile.find(source_player.id).person_id
    assert_equal canonical.id, PlayerProfile.find(canonical_player.id).person_id
    assert_equal (source_coaches.map(&:id) + [coach_profiles(:maria_coach).id]).sort,
                 CoachProfile.where(person_id: canonical.id).pluck(:id).sort
    assert_equal canonical.id, OrganisationMembership.find(northern_membership.id).person_id
    assert_equal canonical.id, OrganisationMembership.find(national_membership.id).person_id
    assert_equal canonical.id, GroupMembership.find(linked_membership.id).person_id
    assert_equal canonical.id, GroupMembership.find(independent_membership.id).person_id
    assert_equal "active", OrganisationMembership.find(northern_membership.id).status
    assert_equal "active", GroupMembership.find(linked_membership.id).status
    assert_equal [organisations(:northern_club).id, organisations(:volleyball_australia).id,
                  organisations(:sydney_club).id].sort, canonical.reload.active_organisation_ids.sort
    assert_equal 3, canonical.group_memberships.count
    assert_equal [source.id, canonical.id], [audit.source_person_id, audit.canonical_person_id]
  end
end
