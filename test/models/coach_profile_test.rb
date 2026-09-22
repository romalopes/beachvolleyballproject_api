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
end