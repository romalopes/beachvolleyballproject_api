require "test_helper"

class PersonAliasTest < ActiveSupport::TestCase
  test "is valid" do
    assert person_aliases(:johnny).valid?
  end

  test "requires a person and a full name" do
    alias_record = PersonAlias.new
    assert_not alias_record.valid?
    assert_includes alias_record.errors.attribute_names, :person
    assert_includes alias_record.errors.attribute_names, :full_name
  end

  test "validates alias type" do
    alias_record = PersonAlias.new(person: people(:one), full_name: "J. Smith", alias_type: "bogus")
    assert_not alias_record.valid?
  end

  test "alias_type is optional" do
    assert PersonAlias.new(person: people(:one), full_name: "J. Smith").valid?
  end
end