require "test_helper"

# Phase 6 (Assessment Sessions), plan §2 / S1: a group is a roster an assessment
# session can be run against.
#
# It is a *selection aid*, so what matters is narrow: membership is unique, the
# slug is generated for new rows, and the visibility flag stays the soft
# presentation rule the rest of the catalogue uses — never an authorization
# boundary.
class GroupTest < ActiveSupport::TestCase
  setup do
    @owner = users(:six)
    @other_coach = users(:three)
    @curator = users(:four)
    @squad = groups(:u19_squad)
    @pedro = player_profiles(:pedro_player)
    @john = player_profiles(:john_player)
    # Membership is keyed on Person (§2.2). `@pedro_person` is deliberately the
    # one with no player profile at all, which is the case the old key could not
    # express.
    @pedro_person = people(:accountless_player)
    @john_person = people(:one)
  end

  test "a group names a roster and records who created it" do
    assert_equal "U19 squad", @squad.name
    assert_equal @owner, @squad.created_by
    assert_predicate @squad, :shared?
    assert_equal "Active", @squad.status_label
  end

  test "a slug is generated from the name for a readable url" do
    group = Group.create!(name: "Beach Elite #{SecureRandom.hex(3)}")

    assert_equal group.name.parameterize, group.slug
  end

  test "a name is required and is stripped" do
    group = Group.new(name: "   ")

    assert_not group.valid?
    assert_includes group.errors.attribute_names, :name
  end

  test "two groups may not share a name, whatever the case" do
    duplicate = Group.new(name: "u19 SQUAD")

    assert_not duplicate.valid?
    assert_includes duplicate.errors.attribute_names, :name
  end

  test "an unknown status or visibility is refused" do
    group = Group.new(name: "Odd #{SecureRandom.hex(3)}", status: "retired", visibility: "secret")

    assert_not group.valid?
    assert_includes group.errors.attribute_names, :status
    assert_includes group.errors.attribute_names, :visibility
  end

  test "a person joins a group once" do
    @squad.group_memberships.create!(person: @john_person)

    duplicate = @squad.group_memberships.build(person: @john_person)

    assert_not duplicate.valid?
    assert_includes duplicate.errors.attribute_names, :person_id
  end

  test "the database refuses a duplicate membership too" do
    @squad.group_memberships.create!(person: @john_person)

    duplicate = @squad.group_memberships.new(person: @john_person)

    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save(validate: false) }
  end

  test "the same person may belong to more than one group" do
    other = Group.create!(name: "Second squad #{SecureRandom.hex(3)}", created_by: @owner)
    other.group_memberships.create!(person: @pedro_person)

    assert_includes @pedro_person.reload.groups, other
    assert_includes @pedro_person.groups, @squad
    # Still reachable from the player profile, through its person.
    assert_includes @pedro.groups, other
  end

  test "a person with no player profile can be on the roster" do
    # The whole reason the key moved (§2.2): a squad has to hold a coach, a parent
    # or a volunteer who never registered as a player.
    volunteer = people(:squad_volunteer)
    assert_nil volunteer.player_profile

    membership = @squad.group_memberships.create!(person: volunteer)

    assert_equal volunteer, membership.person
    assert_includes @squad.reload.people, volunteer
  end

  test "the roster is reachable from both ends and counted" do
    @squad.group_memberships.create!(person: @john_person)

    assert_includes @squad.reload.people, @pedro_person
    assert_includes @squad.people, @john_person
    assert_includes @pedro_person.groups, @squad
    # Fixture owner + Pedro + John.
    assert_equal 3, @squad.player_count
  end

  test "an ended membership is history, and is not counted as a current member" do
    membership = @squad.group_memberships.find_by(person: @pedro_person)

    membership.end_membership!

    assert_predicate membership, :ended?
    # Scoped on the membership, not on `people` — that association resolves to
    # Person, which has no `active` of its own to offer here.
    assert_not_includes @squad.group_memberships.active.pluck(:person_id),
                        @pedro_person.id
    assert_equal 1, @squad.player_count
    # The row survives, which is what keeps a past assessment explicable (§2.5).
    assert GroupMembership.exists?(membership.id)
  end

  test "a person who left can rejoin, and the first stint is kept on the record" do
    membership = @squad.group_memberships.find_by(person: @pedro_person)
    membership.end_membership!
    first_joined_at = membership.joined_at

    membership.update!(status: "active", left_at: nil)

    assert_not_predicate membership.reload, :ended?
    assert_equal first_joined_at.to_i, membership.joined_at.to_i
  end

  test "a private group is visible to its creator and to oversight, not to another coach" do
    private_group = groups(:private_squad)

    assert_includes Group.visible_to(@other_coach).to_a, private_group
    assert_not_includes Group.visible_to(@owner).to_a, private_group
    assert_includes Group.visible_to(@curator).to_a, private_group
  end

  test "a shared group is visible to every coach" do
    assert_includes Group.visible_to(@other_coach).to_a, @squad
    assert_includes Group.visible_to(@owner).to_a, @squad
  end

  test "metadata carries the roster size so a picker can show it without loading members" do
    payload = @squad.metadata

    assert_equal "U19 squad", payload[:name]
    # Pedro plus the fixture owner, who is on the roster like anybody else.
    assert_equal 2, payload[:player_count]
    assert_equal "shared", payload[:visibility]
    assert_equal "Coach Six", payload[:created_by][:name]
    # Ownership is reported from the membership, so it cannot drift from `owner?`.
    assert_equal people(:two).full_name, payload[:owner][:name]
  end

  test "visible_to_user? allows owner, admin, curator and any coach for shared groups" do
    shared = groups(:u19_squad)
    private_group = groups(:private_squad)

    assert shared.visible_to_user?(@other_coach)
    assert shared.visible_to_user?(@owner)
    assert shared.visible_to_user?(@curator)

    assert private_group.visible_to_user?(@other_coach) # other_coach is creator of private_squad in fixtures
    assert private_group.visible_to_user?(@curator)
    assert_not private_group.visible_to_user?(@owner)
  end

  test "destroying a group is restricted when referenced by assessment sessions" do
    session = assessment_sessions(:draft_squad)
    session.update!(group: @squad)

    assert_no_difference "Group.count" do
      assert_not @squad.destroy
    end
    assert @squad.errors[:base].any?
  end

  # --- the group's organisation ---------------------------------------------

  test "a group is refused when its roster does not share its organisation" do
    # national_official belongs to Volleyball Australia and to no club, so putting
    # them on this roster and then naming the club cannot both be allowed.
    @squad.group_memberships.create!(person: people(:national_official))
    @squad.organisation = organisations(:sydney_club)

    assert_not @squad.valid?
    assert_includes @squad.errors.attribute_names, :organisation_id
    assert_match(/share one organisation/, @squad.errors[:organisation_id].first)
  end

  test "a group whose roster does share its organisation is accepted" do
    # people(:two) and people(:accountless_player) are both active in the club.
    @squad.organisation = organisations(:sydney_club)

    assert @squad.valid?
  end

  test "an ended member does not hold a group against its organisation forever" do
    # §2.5 keeps ended rows on the roster as history. Counting them would make the
    # group permanently unsavable for a fact nobody can change.
    @squad.organisation = organisations(:sydney_club)
    outsider = people(:national_official)
    @squad.group_memberships.create!(person: outsider)
    @squad.group_memberships.find_by(person: outsider).end_membership!

    assert_predicate @squad, :valid?
    # Still on the roster as history — the row was never deleted.
    assert_includes @squad.group_memberships.reload.map(&:person_id), outsider.id
  end

  test "a group with no organisation imposes no sharing rule at all" do
    assert_nil @squad.organisation_id
    assert @squad.shares_organisation?([ people(:national_official).id ])
    assert @squad.valid?
  end

end
