require "test_helper"

# Request tests for the coaching-relationship API.
#
# The rules pinned here are the ones that are easy to get wrong and expensive to
# get wrong:
#   * a relationship is *ended*, never deleted — history explains past ratings;
#   * a coach records their own coaching, oversight records anyone's;
#   * a private player does not become visible through a roster row;
#   * `end_date` is not mass-assignable on create, so a new relationship is born
#     open rather than created already finished.
class Api::V1::PlayerCoachesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:two)          # admin, and no coach profile of their own
    @curator = users(:four)       # curator: oversight, not administration
    @coach = users(:six)          # the account behind coach_profiles(:maria_coach)
    @other_coach = users(:three)  # coach role, but no coach profile at all
    @player_user = users(:one)    # player role only

    @maria = coach_profiles(:maria_coach)
    @john = player_profiles(:john_player)
    @pedro = player_profiles(:pedro_player)
  end

  def json
    JSON.parse(response.body)
  end

  def post_json(path, payload)
    post path, params: payload.to_json, headers: { "Content-Type" => "application/json" }
  end

  def patch_json(path, payload)
    patch path, params: payload.to_json, headers: { "Content-Type" => "application/json" }
  end

  def private_player_owned_by(user)
    profile = PlayerProfile.new(display_name: "Private Owned#{SecureRandom.hex(3)}", visibility: "private", created_by: user)
    ProfileOwnership.stamp!(profile, user)
    profile.save!
    profile
  end

  # --- read ------------------------------------------------------------------

  test "index requires authentication" do
    get api_v1_player_coaches_path

    assert_response :unauthorized
  end

  test "a player-role user cannot read coaching relationships" do
    sign_in_as(@player_user)
    get api_v1_player_coaches_path

    assert_response :forbidden
  end

  test "index returns the periods for one player, newest first" do
    sign_in_as(@coach)
    get api_v1_player_coaches_path, params: { player_profile_id: @john.id }

    assert_response :success
    # `ordered` is start_date desc, so the current period leads and the earlier
    # stint follows. That is the order the detail screen renders.
    assert_equal [ player_coaches(:current).id, player_coaches(:resumed_earlier).id ],
                 json["data"].map { |row| row["id"] }
    assert_equal "John Smith", json["data"].first["player_name"]
    assert_equal true, json["data"].first["current"]
    assert_equal false, json["data"].last["current"]
  end

  test "index returns the periods for one coach" do
    sign_in_as(@coach)
    get api_v1_player_coaches_path, params: { coach_profile_id: @maria.id }

    assert_response :success
    assert_equal PlayerCoach.for_coach(@maria.id).count, json["data"].length
    assert_includes json["data"].map { |row| row["id"] }, player_coaches(:historical).id
  end

  test "index separates the current periods from the historical ones" do
    sign_in_as(@coach)

    get api_v1_player_coaches_path, params: { coach_profile_id: @maria.id, status: "current" }
    assert_response :success
    assert_equal [ player_coaches(:current).id ], json["data"].map { |row| row["id"] }

    get api_v1_player_coaches_path, params: { coach_profile_id: @maria.id, status: "historical" }
    assert_response :success
    assert_equal [ player_coaches(:historical).id, player_coaches(:resumed_earlier).id ].sort,
                 json["data"].map { |row| row["id"] }.sort
  end

  test "index rejects an unknown status rather than returning everything" do
    sign_in_as(@coach)
    get api_v1_player_coaches_path, params: { status: "ended" }

    assert_response :unprocessable_entity
    assert_includes json["errors"], "status is not included in the list"
  end

  test "index rejects a non-numeric profile id" do
    sign_in_as(@coach)
    get api_v1_player_coaches_path, params: { player_profile_id: "all" }

    assert_response :unprocessable_entity
    assert_includes json["errors"], "player_profile_id must be a positive integer"
  end

  test "a private player does not become visible through their roster row" do
    # The relationship is a fact, but the player at one end of it is somebody
    # else's private record — an unguarded roster would leak the name the profile
    # endpoint answers 404 for.
    private_player = private_player_owned_by(@other_coach)
    relationship = PlayerCoach.create!(player_profile: private_player, coach_profile: @maria,
                                       start_date: Date.current)

    sign_in_as(@coach)
    get api_v1_player_coaches_path, params: { player_profile_id: private_player.id }

    assert_response :success
    assert_empty json["data"]

    # ...while the coach who recorded the player still sees it.
    sign_in_as(@other_coach)
    get api_v1_player_coaches_path, params: { player_profile_id: private_player.id }

    assert_response :success
    assert_equal [ relationship.id ], json["data"].map { |row| row["id"] }
  end

  test "show returns one relationship, and 404s for an unknown id" do
    sign_in_as(@coach)

    get api_v1_player_coach_path(player_coaches(:historical))
    assert_response :success
    assert_equal Date.new(2025, 11, 30).iso8601, json["end_date"]
    assert_equal "Maria Silva", json["coach_name"]

    get api_v1_player_coach_path(id: 999_999)
    assert_response :not_found
  end

  # --- create ----------------------------------------------------------------

  test "create requires a content creator" do
    sign_in_as(@player_user)
    post_json api_v1_player_coaches_path,
              { player_coach: { player_profile_id: @pedro.id, coach_profile_id: @maria.id } }

    assert_response :forbidden
  end

  test "a coach records their own coaching, starting today" do
    sign_in_as(@coach)
    post_json api_v1_player_coaches_path,
              { player_coach: { player_profile_id: @pedro.id, coach_profile_id: @maria.id } }

    assert_response :created
    # No start date sent, so the period begins today — a relationship is recorded
    # when it starts, and one that began at an unknown point in the past can still
    # be backdated by sending `start_date`.
    assert_equal Date.current.iso8601, json["start_date"]
    assert_equal true, json["current"]
    assert_nil json["end_date"]
  end

  test "create refuses a coach recording a relationship for another coach" do
    sign_in_as(@other_coach)
    post_json api_v1_player_coaches_path,
              { player_coach: { player_profile_id: @pedro.id, coach_profile_id: @maria.id } }

    assert_response :forbidden
    assert_equal "A coach may only record their own coaching relationships", json["error"]
  end

  test "an admin may record a relationship attributed to any coach" do
    # Oversight exists so a club can finish a roster the coach of record never
    # completed — including after that coach has left.
    sign_in_as(@admin)
    post_json api_v1_player_coaches_path,
              { player_coach: { player_profile_id: @pedro.id, coach_profile_id: @maria.id,
                                start_date: "2025-12-01" } }

    assert_response :created
    assert_equal "2025-12-01", json["start_date"]
  end

  test "a curator is refused: curators are oversight for editing, not content creators" do
    # The established convention (see ContentAuthorization): creating a record is
    # content creation, which is coach/admin. Pinned so the boundary is deliberate
    # rather than an accident of which gate ran first.
    sign_in_as(@curator)
    post_json api_v1_player_coaches_path,
              { player_coach: { player_profile_id: @pedro.id, coach_profile_id: @maria.id } }

    assert_response :forbidden
  end

  test "create 404s for an unknown player or coach" do
    sign_in_as(@coach)

    post_json api_v1_player_coaches_path,
              { player_coach: { player_profile_id: 999_999, coach_profile_id: @maria.id } }
    assert_response :not_found
    assert_includes json["errors"], "Player not found"

    post_json api_v1_player_coaches_path,
              { player_coach: { player_profile_id: @pedro.id, coach_profile_id: 999_999 } }
    assert_response :not_found
    assert_includes json["errors"], "Coach not found"
  end

  test "create answers an existing open period with 409 and names the row" do
    sign_in_as(@coach)
    post_json api_v1_player_coaches_path,
              { player_coach: { player_profile_id: @john.id, coach_profile_id: @maria.id } }

    assert_response :conflict
    assert_equal player_coaches(:current).id, json["player_coach"]["id"]
  end

  test "create ignores a client-supplied end date: a new relationship is born open" do
    sign_in_as(@coach)
    post_json api_v1_player_coaches_path,
              { player_coach: { player_profile_id: @pedro.id, coach_profile_id: @maria.id,
                                end_date: "2025-01-01" } }

    assert_response :created
    assert_nil json["end_date"]
    assert_equal true, json["current"]
  end

  test "create refuses an account coaching themselves" do
    account = accounts(:one)
    player = PlayerProfile.create!(display_name: "Dual Player", account: account)
    coach = CoachProfile.create!(display_name: "Dual Coach", account: account)

    sign_in_as(@admin)
    post_json api_v1_player_coaches_path,
              { player_coach: { player_profile_id: player.id, coach_profile_id: coach.id } }

    assert_response :unprocessable_entity
    assert_includes json["errors"], "Coach profile cannot be the same account as the player"
  end

  # --- ending a relationship -------------------------------------------------

  test "ending sets the end date and keeps the row" do
    relationship = player_coaches(:current)
    sign_in_as(@coach)

    post_json end_relationship_api_v1_player_coach_path(relationship), {}

    assert_response :success
    assert_equal Date.current.iso8601, json["end_date"]
    assert_equal false, json["current"]
    # The point of the whole phase: an ended relationship is history, not a
    # deletion. It is what explains a rating recorded while it ran.
    assert PlayerCoach.exists?(relationship.id)
  end

  test "ending can be backdated" do
    relationship = player_coaches(:current)
    sign_in_as(@coach)

    post_json end_relationship_api_v1_player_coach_path(relationship),
              { player_coach: { end_date: "2025-12-31" } }

    assert_response :success
    assert_equal "2025-12-31", json["end_date"]
  end

  test "ending an already-ended relationship is a 409, not a silent overwrite" do
    ended = player_coaches(:historical)
    sign_in_as(@coach)

    post_json end_relationship_api_v1_player_coach_path(ended), {}

    assert_response :conflict
    assert_equal ended.id, json["player_coach"]["id"]
    assert_equal "2025-11-30", json["player_coach"]["end_date"]
  end

  test "ending refuses an unparseable date rather than reopening the period" do
    # Rails would coerce "yesterday" to nil, and nil is exactly the value that
    # means "still coaching" — so the date is parsed explicitly and refused.
    sign_in_as(@coach)
    post_json end_relationship_api_v1_player_coach_path(player_coaches(:current)),
              { player_coach: { end_date: "not-a-date" } }

    assert_response :unprocessable_entity
    assert_includes json["errors"], "end_date is not a valid date"
    assert_predicate player_coaches(:current).reload, :current?
  end

  test "ending refuses a coach acting on another coach's relationship" do
    sign_in_as(@other_coach)
    post_json end_relationship_api_v1_player_coach_path(player_coaches(:current)), {}

    assert_response :forbidden
    assert_predicate player_coaches(:current).reload, :current?
  end

  test "an admin may end any relationship" do
    sign_in_as(@admin)
    post_json end_relationship_api_v1_player_coach_path(player_coaches(:current)), {}

    assert_response :success
    assert_predicate player_coaches(:current).reload, :ended?
  end

  test "there is no delete: a relationship is ended, never destroyed" do
    relationship = player_coaches(:historical)
    sign_in_as(@admin)

    delete api_v1_player_coach_path(relationship)

    assert_response :not_found
    assert PlayerCoach.exists?(relationship.id)
  end

  # --- update ----------------------------------------------------------------

  test "update corrects the dates of a period" do
    relationship = player_coaches(:historical)
    sign_in_as(@coach)

    patch_json api_v1_player_coach_path(relationship),
               { player_coach: { start_date: "2025-02-15", end_date: "2025-11-15" } }

    assert_response :success
    assert_equal "2025-02-15", json["start_date"]
    assert_equal "2025-11-15", json["end_date"]
  end

  test "update refuses to clear an end date" do
    relationship = player_coaches(:historical)
    sign_in_as(@coach)

    patch_json api_v1_player_coach_path(relationship), { player_coach: { end_date: nil } }

    assert_response :unprocessable_entity
    assert_includes json["errors"],
                    "End date cannot be cleared; a resumed relationship is a new period"
    assert_predicate relationship.reload, :ended?
  end

  test "update cannot re-point a relationship at another player or coach" do
    # Re-pointing would silently rewrite what a past assessment was recorded
    # against. Moving a relationship is a new relationship.
    relationship = player_coaches(:historical)
    sign_in_as(@coach)

    patch_json api_v1_player_coach_path(relationship),
               { player_coach: { player_profile_id: @john.id, coach_profile_id: @maria.id,
                                 start_date: "2025-02-01" } }

    assert_response :success
    assert_equal player_coaches(:historical).player_profile_id, json["player_profile_id"]
    assert_equal "Pedro Santos", json["player_name"]
  end

  test "update refuses a coach acting on another coach's relationship" do
    sign_in_as(@other_coach)
    patch_json api_v1_player_coach_path(player_coaches(:historical)),
               { player_coach: { start_date: "2025-03-01" } }

    assert_response :forbidden
  end
end
