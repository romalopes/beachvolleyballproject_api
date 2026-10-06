require "test_helper"

class AccountTest < ActiveSupport::TestCase
  test "is valid and linked to a person" do
    account = accounts(:one)
    assert account.valid?
    assert account.person.present?
    assert_equal "John Smith", account.full_name
  end

  test "every account automatically gets a person on creation" do
    # users(:four), not users(:three): the latter now has an `accounts` fixture so
    # that the user who created `private_squad` can own it, and this test needs a
    # user that genuinely has no account yet.
    user = users(:four)
    account = Account.create!(user: user)

    assert account.person.present?
    assert_equal "Curator", account.person.first_name
    assert_equal "signup", account.person.creation_source
    assert_equal "four@example.com", account.person.email
    assert_equal account.person.email, account.contact_detail.email
  end

  test "every account has exactly one private contact detail" do
    account = accounts(:one)
    assert_equal account.person.first_name, account.contact_detail.first_name
    assert_equal account.person.email, account.contact_detail.email
    assert_equal 1, ContactDetail.where(account_id: account.id).count
  end

  test "account can own multiple player and coach profiles" do
    account = accounts(:one)
    another_player = account.player_profiles.create!(
      person: account.person,
      display_name: "John Smith second record",
      status: "active",
      visibility: "shared"
    )
    coach = account.coach_profiles.create!(
      person: account.person,
      display_name: "John Smith coach record",
      status: "active",
      visibility: "shared"
    )

    assert_includes account.player_profiles.reload, another_player
    assert_includes account.coach_profiles.reload, coach
  end

  test "an account without profiles is valid" do
    account = Account.create!(user: users(:four))

    assert_empty account.player_profiles
    assert_empty account.coach_profiles
    assert account.contact_detail.persisted?
  end

  test "profile Account must agree with the linked Person Account" do
    conflicting_account = Account.create!(user: users(:four))
    profile = PlayerProfile.new(
      account: conflicting_account,
      person: accounts(:one).person,
      status: "active",
      visibility: "shared"
    )

    assert_not profile.valid?
    assert_includes profile.errors[:account], "must match the Account linked to this Person"
  end

  test "contact values assigned to the account are handed to the person" do
    user = users(:four)
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
    assert_equal "+61409999999", account.contact_detail.reload.phone
  end

  test "contact email is separate from login email and editable" do
    account = accounts(:one)
    login_email = account.user.email_address

    account.update!(email: "private@example.net")

    assert_equal "private@example.net", account.contact_detail.reload.email
    assert_equal "private@example.net", account.person.reload.email
    assert_equal login_email, account.user.reload.email_address
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
    account = accounts(:one)
    person = account.person
    assert_not account.destroy
    assert_includes account.errors[:base], "Cannot delete record because a dependent contact detail exists"
    assert Person.exists?(person.id)
  end
end
