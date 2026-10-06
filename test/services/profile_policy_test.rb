require "test_helper"

class ProfilePolicyTest < ActiveSupport::TestCase
  test "a regular Account can view and scope to linked profiles" do
    profile = player_profiles(:john_player)
    profile.update_columns(account_id: accounts(:one).id)
    actor = users(:five)
    policy = ProfilePolicy.new(actor: actor, profile: profile)

    assert policy.view?
    assert_not policy.update?
    assert_includes ProfilePolicy.scope(PlayerProfile.all, actor: actor), profile
    assert accounts(:two).coach?
    assert_not accounts(:one).coach?
  end

  test "a coach can manage visible content but invite and review only profiles they created" do
    coach = users(:three)
    own = PlayerProfile.new(person: people(:accountless_player), display_name: "Coach owned")
    ProfileOwnership.stamp!(own, coach)
    own.save!
    other = player_profiles(:john_player)
    policy = ProfilePolicy.new(actor: coach, profile: other)

    assert policy.view? # shared content remains visible to training managers
    assert policy.update?
    assert_not policy.invite?
    assert_not policy.review_claim?
    assert ProfilePolicy.new(actor: coach, profile: own).invite?
    assert ProfilePolicy.new(actor: coach, profile: own).review_claim?
    assert_not policy.destroy?
  end

  test "private profiles remain hidden from unrelated coaches" do
    private_profile = PlayerProfile.create!(
      person: Person.create!(first_name: "Policy", last_name: "Private", creation_source: "system"),
      visibility: "private",
      created_by: users(:three),
      created_by_account: accounts(:three)
    )

    policy = ProfilePolicy.new(actor: users(:six), profile: private_profile)
    assert_not policy.view?
    assert_not policy.update?
    assert_not policy.invite?
  end

  test "administrators and curators retain their established oversight actions" do
    profile = player_profiles(:john_player)
    admin = ProfilePolicy.new(actor: users(:two), profile: profile)
    curator = ProfilePolicy.new(actor: users(:four), profile: profile)

    assert admin.view?
    assert admin.update?
    assert admin.invite?
    assert admin.review_claim?
    assert admin.merge?
    assert admin.destroy?
    assert curator.view?
    assert_not curator.update?
    assert curator.merge?
    assert_not curator.destroy?
  end
end
