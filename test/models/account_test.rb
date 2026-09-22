require "test_helper"

class AccountTest < ActiveSupport::TestCase
  test "is valid and linked to a person" do
    account = accounts(:one)
    assert account.valid?
    assert account.person.present?
    assert_equal "John Smith", account.full_name
  end

  test "every account automatically gets a person on creation" do
    user = users(:three)
    account = Account.create!(user: user)

    assert account.person.present?
    assert_equal "Coach", account.person.first_name
    assert_equal "signup", account.person.creation_source
    assert_equal "three@example.com", account.person.email
  end

  test "contact values assigned to the account are handed to the person" do
    user = users(:three)
    account = Account.new(user: user)
    account.first_name = "Carlos"
    account.last_name = "Santos"
    account.phone = "+61400000002"

    account.save!
    assert_equal "Carlos", account.person.first_name
    assert_equal "Santos", account.person.last_name
    assert_equal "+61400000002", account.person.phone
    assert_equal "Carlos", account.first_name
  end

  test "updates through the account reach the person" do
    account = accounts(:one)
    account.update!(phone: "+61409999999")
    assert_equal "+61409999999", account.person.reload.phone
    assert_equal "+61409999999", account.reload.phone
  end

  test "person cannot be linked to two accounts" do
    account = Account.new(user: users(:three), person: people(:one))
    assert_not account.valid?
    assert_includes account.errors.full_messages.join, "already linked"
  end

  test "user_id is unique" do
    duplicate = Account.new(user: users(:one), person: people(:two))
    assert_not duplicate.valid?
  end

  test "person survives account destruction" do
    person = accounts(:one).person
    accounts(:one).destroy
    assert Person.exists?(person.id)
  end
end