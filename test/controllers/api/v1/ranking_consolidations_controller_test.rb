require "test_helper"

# Request tests for the Ranking Consolidations API (phase 4): immutable
# snapshots merging several coaches' published session rankings.
class Api::V1::RankingConsolidationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @owner = users(:six)      # coach account linked to maria_coach
    @trainer = users(:three)  # coach role, but not the coach of record
    @admin = users(:two)      # oversight and content creator
    @curator = users(:four)   # oversight only, never a content creator
    @player_user = users(:one)

    @coach = coach_profiles(:maria_coach)
    @definition = assessment_definitions(:balanced)
    @john = player_profiles(:john_player)
    @pedro = player_profiles(:pedro_player)
  end

  # --- helpers ---------------------------------------------------------------

  def json
    JSON.parse(response.body)
  end

  def post_json(path, payload)
    post path, params: payload.to_json, headers: { "Content-Type" => "application/json" }
  end

  def session_path(record)
    "/api/v1/assessment_sessions/#{record.respond_to?(:id) ? record.id : record}"
  end

  def create_draft_session(name:, coach: @coach)
    post_json "/api/v1/assessment_sessions", assessment_session: {
      name: name,
      assessment_definition_id: @definition.id,
      coach_profile_id: coach.id,
      scheduled_on: 3.days.from_now.to_date.iso8601
    }
    assert_response :created
    json["assessment_session"]["id"]
  end

  def add_players!(session_id, players)
    post_json "#{session_path(session_id)}/add_players", players: players
    assert_response :created
    json["assessment_session"]
  end

  def category_cells(values, scale: "one_to_ten")
    @definition.assessment_categories.order(:position, :id).map.with_index do |category, index|
      { assessment_category_id: category.id, scale: scale, value: values[index] }
    end
  end

  # Cells are supplied fully-formed so a test can score a session against a
  # definition other than `@definition`.
  def put_scores!(session_id, cells_by_player)
    put "#{session_path(session_id)}/scores",
        params: { scores: cells_by_player.map { |player_id, cells|
          { player_profile_id: player_id, category_scores: cells }
        } }.to_json,
        headers: { "Content-Type" => "application/json" }
    assert_response :success
  end

  def score_session!(session_id, cells_by_player)
    put_scores!(session_id, cells_by_player.transform_values { |values| category_cells(values) })
  end

  def publish_session!(session_id)
    post "#{session_path(session_id)}/publish"
    assert_response :success
  end

  # Two fully-scored, published sessions sharing the definition. Session A
  # ranks john 80 / pedro 70; session B ranks john 60 / pedro 70.
  # Consolidated: john avg 70, pedro avg 70 → tied rank 1, both coverage 2.
  def two_published_sessions
    sign_in_as(@owner)
    first = create_draft_session(name: "First screening")
    add_players!(first, [ { player_profile_id: @john.id }, { player_profile_id: @pedro.id } ])
    score_session!(first, { @john.id => [ 8, 7, 9 ], @pedro.id => [ 7, 6, 8 ] })
    publish_session!(first)

    second = create_draft_session(name: "Second screening")
    add_players!(second, [ { player_profile_id: @john.id }, { player_profile_id: @pedro.id } ])
    score_session!(second, { @john.id => [ 6, 5, 7 ], @pedro.id => [ 7, 6, 8 ] })
    publish_session!(second)

    [ first, second ]
  end

  def create_consolidation(definition_id: @definition.id, session_ids:, name: "Club ranking")
    post_json "/api/v1/ranking_consolidations", ranking_consolidation: {
      name: name,
      assessment_definition_id: definition_id,
      assessment_session_ids: session_ids
    }
  end
  # --- index / show ----------------------------------------------------------

  test "index requires authentication" do
    get "/api/v1/ranking_consolidations"
    assert_response :unauthorized
  end

  test "index refuses a player-role user" do
    sign_in_as(@player_user)
    get "/api/v1/ranking_consolidations"
    assert_response :forbidden
  end

  test "index lists consolidations to a training manager" do
    first, second = two_published_sessions
    create_consolidation(session_ids: [ first, second ])
    assert_response :created

    get "/api/v1/ranking_consolidations"
    assert_response :success
    assert_equal 1, json["ranking_consolidations"].size
    entry = json["ranking_consolidations"].first
    assert_equal "Club ranking", entry["name"]
    assert_equal 2, entry["session_count"]
    assert_equal 2, entry["player_count"]
  end

  test "show returns the frozen snapshot with per-session scores" do
    first, second = two_published_sessions
    create_consolidation(session_ids: [ first, second ])
    assert_response :created
    id = json["ranking_consolidation"]["id"]

    get "/api/v1/ranking_consolidations/#{id}"
    assert_response :success
    body = json["ranking_consolidation"]

    assert_equal 2, body["assessment_sessions"].size
    assert_equal 2, body["rows"].size

    rows = body["rows"].to_h { |row| [ row["player_profile_id"], row ] }
    assert_equal 1, rows[@john.id]["rank"]
    assert_equal 1, rows[@pedro.id]["rank"]
    assert_equal 70, rows[@john.id]["average_score"]
    assert_equal 70, rows[@pedro.id]["average_score"]
    assert_equal 2, rows[@john.id]["coverage"]
    assert_equal first.to_s, rows[@john.id]["coach_scores"].keys.min
  end

  # --- create ----------------------------------------------------------------

  test "a guest cannot create a consolidation" do
    post_json "/api/v1/ranking_consolidations", ranking_consolidation: {
      assessment_definition_id: @definition.id, assessment_session_ids: []
    }
    assert_response :unauthorized
  end

  test "a player cannot create a consolidation" do
    sign_in_as(@player_user)
    create_consolidation(session_ids: [])
    assert_response :forbidden
  end

  test "a curator may view but never create a consolidation" do
    first, second = two_published_sessions

    sign_in_as(@curator)
    create_consolidation(session_ids: [ first, second ])
    assert_response :forbidden

    get "/api/v1/ranking_consolidations"
    assert_response :success
  end
  test "create refuses a draft session" do
    sign_in_as(@owner)
    draft = create_draft_session(name: "Unfinished")
    add_players!(draft, [ { player_profile_id: @john.id } ])

    create_consolidation(session_ids: [ draft ])
    assert_response :unprocessable_entity
    assert_match(/not published/, json["errors"].join(" "))
    assert_equal 0, RankingConsolidation.count
  end

  test "create refuses sessions on a different definition" do
    sign_in_as(@owner)
    other_definition = AssessmentDefinition.create!(
      name: "Other rubric", status: "active", created_by: @owner,
      assessment_categories_attributes: [
        { category_id: categories(:assessment_rubric).id, weight: 100, position: 0 }
      ]
    )
    other = create_draft_session(name: "Other session")
    # Re-point the draft at the other definition directly: the create endpoint
    # only accepts the active balanced definition in this setup.
    AssessmentSession.find(other).update_column(:assessment_definition_id, other_definition.id)
    add_players!(other, [ { player_profile_id: @john.id } ])
    # Score against the *other* definition's single category, so the session is
    # genuinely complete and the only thing wrong with it is its definition.
    other_category = other_definition.assessment_categories.order(:position, :id).first
    put_scores!(other, { @john.id => [ { assessment_category_id: other_category.id,
                                         scale: "one_to_ten", value: 8 } ] })
    publish_session!(other)

    create_consolidation(session_ids: [ other ])
    assert_response :unprocessable_entity
    assert_match(/different assessment definition/, json["errors"].join(" "))
    assert_equal 0, RankingConsolidation.count
  end

  # `publish` already refuses an incomplete roster, so a normally-produced
  # published session is always complete. This guard defends the merge against
  # data that drifts *after* publish (an out-of-band edit, an import, a future
  # scoring change): rather than averaging a partial score into the club ranking,
  # the builder refuses and names the players affected.
  test "create refuses a published session whose scores drifted incomplete" do
    sign_in_as(@owner)
    session_id = create_draft_session(name: "Drifted after publish")
    add_players!(session_id, [ { player_profile_id: @john.id }, { player_profile_id: @pedro.id } ])
    score_session!(session_id, { @john.id => [ 8, 7, 9 ], @pedro.id => [ 7, 6, 8 ] })
    publish_session!(session_id)

    # Drop one of pedro's category score rows behind the app's back. (Blanking
    # the score instead would be rejected by the score-pair check constraint.)
    pedro_assessment = AssessmentSession.find(session_id).assessments
                                                .find_by(player_profile_id: @pedro.id)
    AssessmentCategoryScore.where(assessment_id: pedro_assessment.id)
                           .order(:assessment_category_id)
                           .first
                           .delete

    create_consolidation(session_ids: [ session_id ])
    assert_response :unprocessable_entity
    assert_match(/incomplete/, json["errors"].join(" "))
    assert_equal 0, RankingConsolidation.count
  end

  test "a draft session is refused before coverage is considered" do
    sign_in_as(@owner)
    session_id = create_draft_session(name: "Still a draft")
    add_players!(session_id, [ { player_profile_id: @john.id } ])
    score_session!(session_id, { @john.id => [ 8, 7, 9 ] })

    create_consolidation(session_ids: [ session_id ])
    assert_response :unprocessable_entity
    assert_match(/not published/, json["errors"].join(" "))
    assert_equal 0, RankingConsolidation.count
  end

  test "create reports an unknown session id without writing anything" do
    sign_in_as(@owner)
    first, _second = two_published_sessions

    create_consolidation(session_ids: [ first, 999_999 ])
    assert_response :unprocessable_entity
    assert_match(/not found/, json["errors"].join(" "))
    assert_equal 0, RankingConsolidation.count
  end

  test "create requires at least one session" do
    sign_in_as(@owner)
    create_consolidation(session_ids: [])
    assert_response :unprocessable_entity
    assert_equal 0, RankingConsolidation.count
  end

  test "a partially overlapping roster averages over covered sessions only" do
    sign_in_as(@owner)
    first = create_draft_session(name: "Both players")
    add_players!(first, [ { player_profile_id: @john.id }, { player_profile_id: @pedro.id } ])
    score_session!(first, { @john.id => [ 8, 7, 9 ], @pedro.id => [ 7, 6, 8 ] })
    publish_session!(first)

    second = create_draft_session(name: "John only")
    add_players!(second, [ { player_profile_id: @john.id } ])
    score_session!(second, { @john.id => [ 6, 5, 7 ] })
    publish_session!(second)

    create_consolidation(session_ids: [ first, second ])
    assert_response :created
    rows = json["ranking_consolidation"]["rows"].to_h { |row| [ row["player_profile_id"], row ] }

    # john: (80 + 60) / 2 = 70 over 2 sessions; pedro: 70 over 1 session.
    # Same average → shared rank, and pedro's coverage says 1, never a zero
    # from the session he was not part of.
    assert_equal 70, rows[@john.id]["average_score"]
    assert_equal 70, rows[@pedro.id]["average_score"]
    assert_equal 2, rows[@john.id]["coverage"]
    assert_equal 1, rows[@pedro.id]["coverage"]
    assert_equal 1, rows[@john.id]["rank"]
    assert_equal 1, rows[@pedro.id]["rank"]
  end

  test "withdrawing a source session leaves the consolidation unchanged" do
    first, second = two_published_sessions
    create_consolidation(session_ids: [ first, second ])
    assert_response :created
    id = json["ranking_consolidation"]["id"]
    before = json["ranking_consolidation"]["rows"]

    AssessmentSession.find(first).update!(status: "withdrawn")

    get "/api/v1/ranking_consolidations/#{id}"
    assert_response :success
    assert_equal before, json["ranking_consolidation"]["rows"]
  end
end
