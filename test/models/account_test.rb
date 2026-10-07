require "test_helper"

class AccountTest < ActiveSupport::TestCase
  test "is valid and reads private details from ContactDetail" do
    account = accounts(:one)
    assert account.valid?
    assert_equal "John Smith", account.full_name
    assert_equal "one@example.com", account.email
  end

  test "every account automatically gets one ContactDetail on creation" do
    user = User.create!(email_address: "curator-four@example.com", password: "password123")
    account = Account.create!(user: user)

    assert account.contact_detail.persisted?
    assert_equal "curator-four", account.contact_detail.first_name
    assert_nil account.contact_detail.last_name
    assert_equal "curator-four@example.com", account.contact_detail.email
    assert_equal 1, ContactDetail.where(account_id: account.id).count
  end

  test "account can own multiple player and coach profiles without a Person association" do
    account = accounts(:one)
    another_player = account.player_profiles.create!(display_name: "John second record", status: "active", visibility: "shared")
    coach = account.coach_profiles.create!(display_name: "John coach record", status: "active", visibility: "shared")

    assert_includes account.player_profiles.reload, another_player
    assert_includes account.coach_profiles.reload, coach
    assert_not_respond_to account, :person
  end

  test "an account without profiles is valid" do
    account = create_account!(first_name: "Profileless", last_name: "Account")

    assert_empty account.player_profiles
    assert_empty account.coach_profiles
    assert account.contact_detail.persisted?
  end

  test "contact fields update ContactDetail and stay separate from login credentials" do
    account = accounts(:one)
    login_email = account.user.email_address

    account.update!(first_name: "Carlos", last_name: "Santos", phone: "+61409999999", email: "private@example.net")

    assert_equal "Carlos Santos", account.reload.full_name
    assert_equal "+61409999999", account.contact_detail.reload.phone
    assert_equal "private@example.net", account.contact_detail.email
    assert_equal login_email, account.user.reload.email_address
  end

  test "Account has no Person foreign key or association" do
    assert_not_respond_to accounts(:one), :person
    assert_not Account.column_names.include?("person_id")
    assert_not_respond_to users(:one), :person
  end

  test "user_id remains unique" do
    duplicate = Account.new(user: accounts(:one).user)
    assert_not duplicate.valid?
  end

  test "destroying an account removes its private details and leaves roster identity untouched" do
    account = create_account!(first_name: "Disposable", last_name: "Account")
    detail_id = account.contact_detail.id

    assert account.destroy
    assert_not ContactDetail.exists?(detail_id)
  end
end
