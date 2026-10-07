require "test_helper"

class CoachProfileTest < ActiveSupport::TestCase
  test "is valid" do
    assert coach_profiles(:maria_coach).valid?
  end

  test "a coach profile requires a display name when it has no account" do
    profile = CoachProfile.new
    assert_not profile.valid?
    assert_includes profile.errors.attribute_names, :display_name

    assert CoachProfile.new(account: accounts(:two)).valid?
    assert CoachProfile.new(display_name: "Alex Coach").valid?
    assert_not CoachProfile.new.valid?
  end

  test "an account may have multiple coach profiles" do
    account = accounts(:two)
    assert CoachProfile.new(account: account).valid?
    assert CoachProfile.new(account: account).valid?
  end

  test "validates status" do
    profile = CoachProfile.new(display_name: "Invalid", status: "bogus")
    assert_not profile.valid?
  end

  test "visibility defaults to shared and follows the same rules as players" do
    profile = coach_profiles(:maria_coach)
    assert_equal "shared", profile.visibility

    owner = users(:three)
    private_profile = CoachProfile.create!(
      display_name: "Quiet Coach",
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
