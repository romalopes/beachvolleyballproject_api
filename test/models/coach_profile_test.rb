require "test_helper"

class CoachProfileTest < ActiveSupport::TestCase
  test "is valid" do
    assert coach_profiles(:maria_coach).valid?
  end

  # Phase 18 reversed Phase 2's "requires a person": a coach recorded with only
  # a display name is the state a claim invitation is issued against, exactly as
  # for a player. The name is what identifies it in the meantime.
  test "a personless coach profile requires a display name instead of a person" do
    profile = CoachProfile.new
    assert_not profile.valid?
    assert_includes profile.errors.attribute_names, :display_name

    # A profile with a Person needs no display name: that is the normal case.
    assert CoachProfile.new(person_id: people(:two).id).valid?
    assert CoachProfile.new(display_name: "Alex Coach").valid?
    # Neither a Person nor a name: nothing identifies this profile.
    assert_not CoachProfile.new.valid?
  end

  test "a person may have multiple coach profiles" do
    person = people(:two)
    assert CoachProfile.new(person: person).valid?
    assert CoachProfile.new(person: person).valid?
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
