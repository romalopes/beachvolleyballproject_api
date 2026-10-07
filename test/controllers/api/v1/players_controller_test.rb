require "test_helper"

class Api::V1::PlayersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @public_user = users(:one)
    @trainer = users(:three)
    @other_coach = users(:six)
    @admin = users(:two)
    @curator = users(:four)
  end

  test "index returns active player profiles" do
    sign_in_as(@admin)
    get api_v1_players_path
    assert_response :success
    ids = JSON.parse(response.body).fetch("data").map { |row| row.fetch("id") }
    assert_includes ids, player_profiles(:john_player).id
    assert_includes ids, player_profiles(:pedro_player).id
  end

  test "regular account scopes to linked profiles" do
    linked = player_profiles(:john_player)
    linked.update_columns(account_id: accounts(:one).id)
    sign_in_as(accounts(:one).user)
    get api_v1_players_path
    assert_response :success
    assert_equal [ linked.id ], JSON.parse(response.body).fetch("data").map { |row| row.fetch("id") }
    get api_v1_player_path(linked)
    assert_response :success
  end

  test "create requires manager and stamps creator account" do
    sign_in_as(@public_user)
    post api_v1_players_path, params: player_create_params
    assert_response :forbidden

    sign_out
    sign_in_as(@trainer)
    post api_v1_players_path, params: player_create_params
    assert_response :created
    profile = PlayerProfile.find(JSON.parse(response.body).fetch("id"))
    assert_equal "Test User", profile.display_name
    assert_nil profile.account_id
    assert_equal accounts(:three).id, profile.created_by_account_id
  end

  test "client supplied ownership fields are ignored" do
    sign_in_as(@trainer)
    post api_v1_players_path, params: {
      player: { player_profile: { display_name: "Untrusted Owner", account_id: accounts(:one).id, created_by_account_id: accounts(:one).id } }
    }
    assert_response :created
    profile = PlayerProfile.find(JSON.parse(response.body).fetch("id"))
    assert_nil profile.account_id
    assert_equal accounts(:three).id, profile.created_by_account_id
  end

  test "index paginates player profiles" do
    sign_in_as(@admin)
    baseline = PlayerProfile.count
    25.times { |index| PlayerProfile.create!(display_name: "Paged #{format('%02d', index)}") }
    get api_v1_players_path
    first = JSON.parse(response.body)
    assert_equal 20, first.dig("meta", "per_page")
    assert_equal baseline + 25, first.dig("meta", "total")
    get api_v1_players_path, params: { page: 2 }
    second = JSON.parse(response.body)
    assert_empty first.fetch("data").map { |row| row.fetch("id") } & second.fetch("data").map { |row| row.fetch("id") }
  end

  test "invalid profile attributes return validation errors" do
    sign_in_as(@admin)
    post api_v1_players_path, params: { player: { player_profile: { display_name: "" } } }
    assert_response :unprocessable_entity
    patch api_v1_player_path(player_profiles(:pedro_player)), params: { player: { player_profile: { visibility: "bogus" } } }
    assert_response :unprocessable_entity
  end

  test "show and update use player profile attributes" do
    player = player_profiles(:pedro_player)
    sign_in_as(@admin)
    get api_v1_player_path(player)
    assert_response :success
    assert_equal player.id, JSON.parse(response.body).fetch("id")
    patch api_v1_player_path(player), params: { player: { player_profile: { level: "advanced" } } }
    assert_response :success
    assert_equal "advanced", player.reload.level
  end

  test "private players are hidden from unrelated coaches but visible to owner and curator" do
    private_player = private_player_owned_by(@trainer)
    sign_in_as(@other_coach)
    get api_v1_players_path
    assert_not_includes JSON.parse(response.body).fetch("data").map { |row| row.fetch("id") }, private_player.id
    get api_v1_player_path(private_player)
    assert_response :not_found

    sign_out
    sign_in_as(@trainer)
    get api_v1_player_path(private_player)
    assert_response :success

    sign_out
    sign_in_as(@curator)
    get api_v1_player_path(private_player)
    assert_response :success
  end

  test "only owner or admin can flip visibility" do
    private_player = private_player_owned_by(@trainer)
    sign_in_as(@other_coach)
    patch api_v1_player_path(private_player), params: { player: { player_profile: { visibility: "shared" } } }
    assert_response :not_found

    private_player.update!(visibility: "shared")
    patch api_v1_player_path(private_player), params: { player: { player_profile: { visibility: "private" } } }
    assert_response :forbidden

    sign_out
    sign_in_as(@trainer)
    patch api_v1_player_path(private_player), params: { player: { player_profile: { visibility: "private" } } }
    assert_response :success

    sign_out
    sign_in_as(@admin)
    patch api_v1_player_path(private_player), params: { player: { player_profile: { visibility: "shared" } } }
    assert_response :success
  end

  test "status filter exposes archived players on request" do
    sign_in_as(@admin)
    player = player_profiles(:pedro_player)
    player.update!(status: "archived")
    get api_v1_players_path
    assert_not_includes JSON.parse(response.body).fetch("data").map { |row| row.fetch("id") }, player.id
    get api_v1_players_path, params: { status: "archived" }
    assert_includes JSON.parse(response.body).fetch("data").map { |row| row.fetch("id") }, player.id
  end

  test "show exposes assessment count and visible history" do
    sign_in_as(@trainer)
    get api_v1_player_path(player_profiles(:pedro_player))
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 1, body.fetch("assessment_count")
    assert_includes body.fetch("assessments").map { |row| row.fetch("id") }, assessments(:skill_active).id
  end

  private

  def private_player_owned_by(owner)
    profile = PlayerProfile.new(display_name: "Private Owned", visibility: "private", created_by: owner)
    ProfileOwnership.stamp!(profile, owner)
    profile.save!
    profile
  end

  def player_create_params
    { player: { player_profile: { display_name: "Test User", preferred_position: "setter" } } }
  end
end