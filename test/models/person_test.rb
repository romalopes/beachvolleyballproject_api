require "test_helper"

class PersonTest < ActiveSupport::TestCase
  test "is valid with a first name" do
    assert people(:one).valid?
  end

  test "requires first_name" do
    person = Person.new
    assert_not person.valid?
    assert_includes person.errors.attribute_names, :first_name
  end

  test "can exist without an Account, PlayerProfile or CoachProfile" do
    person = Person.new(first_name: "Ana")
    assert person.valid?
    assert_nil person.account
    assert_nil person.player_profile
    assert_nil person.coach_profile
  end

  test "can be a player and a coach simultaneously" do
    person = Person.new(first_name: "Ana")
    person.build_player_profile(level: "advanced")
    person.build_coach_profile(coaching_level: "level_1")
    assert person.valid?
  end

  test "rejects future date of birth" do
    person = Person.new(first_name: "Ana", date_of_birth: 1.day.from_now.to_date)
    assert_not person.valid?
    assert_includes person.errors.attribute_names, :date_of_birth
  end

  test "validates status and creation_source" do
    person = Person.new(first_name: "Ana", status: "bogus")
    assert_not person.valid?

    person = Person.new(first_name: "Ana", creation_source: "bogus")
    assert_not person.valid?
  end

  test "accountless player fixture has no account but has a player profile" do
    person = people(:accountless_player)
    assert_nil person.account
    assert person.player_profile.present?
    assert_equal "coach_created", person.creation_source
  end

  test "full_name joins first and last name" do
    assert_equal "John Smith", people(:one).full_name
    assert_equal "Old", Person.new(first_name: "Old").full_name
  end

  test "canonical scope excludes merged people" do
    assert_not_includes Person.canonical, people(:merged)
    assert_includes Person.canonical, people(:one)
  end

  test "canonical_person follows the merge chain" do
    assert_equal people(:one), people(:merged).canonical_person
    assert_equal people(:one), people(:one).canonical_person
  end

  test "cannot merge into itself" do
    person = people(:one)
    person.merged_into = person
    assert_not person.valid?
    assert_includes person.errors.attribute_names, :merged_into
  end

  test "aliases are available for duplicate detection" do
    assert_equal %w[Johnny\ Smith João\ Smith].sort, people(:one).person_aliases.pluck(:full_name).sort
  end
end