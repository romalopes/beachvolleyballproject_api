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

  test "a player joins a group once" do
    @squad.group_memberships.create!(player_profile: @john)

    duplicate = @squad.group_memberships.build(player_profile: @john)

    assert_not duplicate.valid?
    assert_includes duplicate.errors.attribute_names, :player_profile_id
  end

  test "the database refuses a duplicate membership too" do
    @squad.group_memberships.create!(player_profile: @john)

    duplicate = @squad.group_memberships.new(player_profile: @john)

    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save(validate: false) }
  end

  test "the same player may belong to more than one group" do
    other = Group.create!(name: "Second squad #{SecureRandom.hex(3)}", created_by: @owner)
    other.group_memberships.create!(player_profile: @pedro)

    assert_includes @pedro.reload.groups, other
    assert_includes @pedro.groups, @squad
  end

  test "the roster is reachable from both ends and counted" do
    @squad.group_memberships.create!(player_profile: @john)

    assert_includes @squad.reload.player_profiles, @pedro
    assert_includes @squad.player_profiles, @john
    assert_includes @pedro.groups, @squad
    assert_equal 2, @squad.player_count
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
    assert_equal 1, payload[:player_count]
    assert_equal "shared", payload[:visibility]
    assert_equal "Coach Six", payload[:created_by][:name]
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
end
