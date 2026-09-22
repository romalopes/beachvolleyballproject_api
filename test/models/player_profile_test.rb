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

  test "full_name delegates to person" do
    assert_equal "John Smith", player_profiles(:john_player).full_name
  end
end