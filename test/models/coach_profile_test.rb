require "test_helper"

class CoachProfileTest < ActiveSupport::TestCase
  test "is valid" do
    assert coach_profiles(:maria_coach).valid?
  end

  test "requires a person" do
    profile = CoachProfile.new
    assert_not profile.valid?
    assert_includes profile.errors.attribute_names, :person
  end

  test "a person can have only one coach profile" do
    duplicate = CoachProfile.new(person: people(:two))
    assert_not duplicate.valid?
    assert_includes duplicate.errors.attribute_names, :person_id
  end

  test "validates status" do
    profile = CoachProfile.new(person: people(:one), status: "bogus")
    assert_not profile.valid?
  end

  test "visibility defaults to shared and follows the same rules as players" do
    profile = coach_profiles(:maria_coach)
    assert_equal "shared", profile.visibility

    owner = users(:three)
    private_profile = CoachProfile.create!(
      person: Person.create!(first_name: "Quiet", last_name: "Coach", creation_source: "coach_created"),
      visibility: "private", created_by: owner
    )

    assert private_profile.visible_to_user?(owner)
    assert private_profile.visible_to_user?(users(:four)) # curator
    assert private_profile.visible_to_user?(users(:two))  # admin
    assert_not private_profile.visible_to_user?(users(:six)) # another coach
    assert private_profile.visibility_change_permitted?(owner)
    assert_not private_profile.visibility_change_permitted?(users(:six))
  end
end