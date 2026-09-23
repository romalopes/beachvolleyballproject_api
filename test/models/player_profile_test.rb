require "test_helper"

class PlayerProfileTest < ActiveSupport::TestCase
  test "is valid" do
    assert player_profiles(:john_player).valid?
  end

  test "requires a person" do
    profile = PlayerProfile.new
    assert_not profile.valid?
    assert_includes profile.errors.attribute_names, :person
  end

  test "a person can have only one player profile" do
    duplicate = PlayerProfile.new(person: people(:one))
    assert_not duplicate.valid?
    assert_includes duplicate.errors.attribute_names, :person_id
  end

  test "different people can each have a player profile" do
    assert PlayerProfile.new(person: people(:two)).valid?
  end

  test "validates status" do
    profile = PlayerProfile.new(person: people(:two), status: "bogus")
    assert_not profile.valid?
  end

  test "visibility defaults to shared and validates" do
    profile = player_profiles(:john_player)
    assert_equal "shared", profile.visibility
    assert profile.valid?

    profile.visibility = "bogus"
    assert_not profile.valid?
    assert_includes profile.errors.attribute_names, :visibility
  end

  test "visible_to hides other coaches' private profiles but not owner, curator or admin" do
    owner = users(:three)   # coach
    other_coach = users(:two) # coach + admin — use a pure coach below via roles
    assert other_coach.coach?

    private_profile = PlayerProfile.create!(
      person: Person.create!(first_name: "Solo", last_name: "Hidden", creation_source: "coach_created"),
      visibility: "private", created_by: owner
    )

    assert_includes PlayerProfile.visible_to(owner).map(&:id), private_profile.id
    assert_includes PlayerProfile.visible_to(users(:four)).map(&:id), private_profile.id # curator
    assert_includes PlayerProfile.visible_to(users(:two)).map(&:id), private_profile.id  # admin

    pure_other = users(:six) # coach only
    assert_not_includes PlayerProfile.visible_to(pure_other).map(&:id), private_profile.id
    assert_not private_profile.visible_to_user?(pure_other)
    assert private_profile.visible_to_user?(owner)
  end

  test "visibility switch is only for the owner or an admin" do
    owner = users(:three)
    profile = PlayerProfile.create!(
      person: Person.create!(first_name: "Mine", last_name: "Only", creation_source: "coach_created"),
      visibility: "private", created_by: owner
    )

    assert profile.visibility_change_permitted?(owner)
    assert profile.visibility_change_permitted?(users(:two)) # admin
    assert_not profile.visibility_change_permitted?(users(:six)) # another coach
    assert_not profile.visibility_change_permitted?(users(:four)) # curator
  end

  test "full_name delegates to person" do
    assert_equal "John Smith", player_profiles(:john_player).full_name
  end
end