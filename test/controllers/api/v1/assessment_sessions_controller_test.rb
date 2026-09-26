require "test_helper"

# Request tests for the Assessment Sessions API: one coach, many players,
# weighted scores, and a session-level publish authority.
class Api::V1::AssessmentSessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @owner = users(:six)      # coach account linked to maria_coach
    @trainer = users(:three)  # coach role, but not the coach of record
    @admin = users(:two)      # oversight and content creator
    @curator = users(:four)   # oversight only
    @player_user = users(:one)

    @coach = coach_profiles(:maria_coach)
    @definition = assessment_definitions(:balanced)
    @draft = assessment_sessions(:draft_squad)
    @published = assessment_sessions(:published_squad)
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

  def patch_json(path, payload)
    patch path, params: payload.to_json, headers: { "Content-Type" => "application/json" }
  end

  def put_json(path, payload)
    put path, params: payload.to_json, headers: { "Content-Type" => "application/json" }
  end

  def session_path(record)
    "/api/v1/assessment_sessions/#{record.respond_to?(:id) ? record.id : record}"
  end

  def create_draft_session(name: "Squad screening")
    post_json "/api/v1/assessment_sessions", assessment_session: {
      name: name,
      assessment_definition_id: @definition.id,
      coach_profile_id: @coach.id,
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

  # --- index / show ----------------------------------------------------------

  test "index requires authentication" do
    get "/api/v1/assessment_sessions"
    assert_response :unauthorized
  end

  test "index refuses a player-role user" do
    sign_in_as(@player_user)
    get "/api/v1/assessment_sessions"
    assert_response :forbidden
  end

  test "index exposes definition columns, roster state, and no fabricated totals" do
    sign_in_as(@trainer)
    get "/api/v1/assessment_sessions"

    assert_response :success
    body = json
    assert_kind_of Array, body["assessment_sessions"]

    draft = body["assessment_sessions"].find { |row| row["id"] == @draft.id }
    assert_equal "Tuesday squad screening", draft["name"]
    assert_equal "draft", draft["status"]
    assert_equal "Maria Silva", draft["coach_profile"]["full_name"]
    assert_equal %w[Attack Defense Serve],
                 draft["assessment_definition"]["assessment_categories"].map { |row| row["label"] }
    assert_equal [ 40, 30, 30 ],
                 draft["assessment_definition"]["assessment_categories"].map { |row| row["weight"] }

    john = draft["participants"].find { |row| row["player_profile_id"] == @john.id }
    pedro = draft["participants"].find { |row| row["player_profile_id"] == @pedro.id }
    assert_equal "John Smith", john["player_name"]
    assert_equal "incomplete", john["result"]["status"]
    assert_nil john["result"]["overall_score"]
    assert_equal 3, john["result"]["missing_category_ids"].size
    assert_equal "excluded", pedro["result"]["status"]
    assert_equal "Injured knee, not observed this session.", pedro["missing_reason"]
    assert_equal [], draft["ranking"]["ranking"], "an unscored roster has no ranking"
  end

  test "show returns the complete session payload to a training manager" do
    sign_in_as(@curator)
    get session_path(@published)

    assert_response :success
    body = json["assessment_session"]
    assert_equal @published.name, body["name"]
    assert_equal "published", body["status"]
    assert_not_nil body["published_at"]
    assert_equal @coach.id, body["coach_profile_id"]
    assert body["ranking"].key?("incomplete")
  end

  # --- create ----------------------------------------------------------------

  test "the coach of record creates a draft session and cannot spoof the creator" do
    sign_in_as(@owner)
    assert_difference -> { AssessmentSession.count }, 1 do
      post_json "/api/v1/assessment_sessions", assessment_session: {
        name: "May screening",
        assessment_definition_id: @definition.id,
        coach_profile_id: @coach.id,
        scheduled_on: 10.days.from_now.to_date.iso8601,
        created_by_id: @player_user.id
      }
    end

    assert_response :created
    body = json["assessment_session"]
    assert_equal "draft", body["status"]
    assert_equal @owner.id, body["created_by_id"]
    assert_equal @coach.id, body["coach_profile_id"]
    assert_equal "Maria Silva", body["coach_profile"]["full_name"]
  end

  test "a guest cannot create a session" do
    assert_no_difference("AssessmentSession.count") do
      post_json "/api/v1/assessment_sessions", assessment_session: {
        assessment_definition_id: @definition.id, coach_profile_id: @coach.id
      }
    end

    assert_response :unauthorized
  end

  test "a player cannot create a session" do
    sign_in_as(@player_user)
    assert_no_difference("AssessmentSession.count") do
      post_json "/api/v1/assessment_sessions", assessment_session: {
        assessment_definition_id: @definition.id, coach_profile_id: @coach.id
      }
    end

    assert_response :forbidden
  end

  test "another coach cannot create a session attributed to somebody else" do
    sign_in_as(@trainer)
    assert_no_difference("AssessmentSession.count") do
      post_json "/api/v1/assessment_sessions", assessment_session: {
        name: "Not mine",
        assessment_definition_id: @definition.id,
        coach_profile_id: @coach.id
      }
    end

    assert_response :forbidden
  end

  test "create refuses a definition that is still a draft" do
    sign_in_as(@owner)
    assert_no_difference("AssessmentSession.count") do
      post_json "/api/v1/assessment_sessions", assessment_session: {
        name: "Draft template",
        assessment_definition_id: assessment_definitions(:pre_season).id,
        coach_profile_id: @coach.id
      }
    end

    assert_response :unprocessable_entity
    assert_includes json["errors"].join(" "), "must be active"
  end

  # --- update ----------------------------------------------------------------

  test "the coach of record may edit a draft session" do
    sign_in_as(@owner)
    patch_json session_path(@draft), assessment_session: { name: "Tuesday screening (renamed)" }

    assert_response :success
    assert_equal "Tuesday screening (renamed)", @draft.reload.name
  end

  test "a published session is archival and cannot be edited" do
    sign_in_as(@owner)
    patch_json session_path(@published), assessment_session: { name: "Tampered" }

    assert_response :unprocessable_entity
    assert_includes json["error"], "Only draft"
    assert_equal "Spring evaluation", @published.reload.name
  end

  test "a coach who is not the coach of record cannot edit the session" do
    sign_in_as(@trainer)
    patch_json session_path(@draft), assessment_session: { name: "Tampered" }

    assert_response :forbidden
    assert_equal "Tuesday squad screening", @draft.reload.name
  end

  test "oversight may edit a draft session" do
    sign_in_as(@curator)
    patch_json session_path(@draft), assessment_session: { notes: "Curator note." }

    assert_response :success
    assert_equal "Curator note.", @draft.reload.notes
  end

  # --- roster ----------------------------------------------------------------

  test "the roster accepts existing players and inline-created players" do
    sign_in_as(@owner)
    session_id = create_draft_session
    body = add_players!(session_id, [ { player_profile_id: @john.id, inclusion: "included" } ])
    assert_equal 1, body["participants"].size
    assert_equal @john.id, body["participants"].first["player_profile_id"]

    assert_difference [ "Person.count", "PlayerProfile.count" ], 1 do
      assert_no_difference("Account.count") do
        post_json "#{session_path(session_id)}/add_players", players: [
          { person: { first_name: "Inline", last_name: "Player" }, inclusion: "included" }
        ]
      end
    end

    assert_response :created
    inline = json["assessment_session"]["participants"].find do |row|
      row["player_name"] == "Inline Player"
    end
    assert_not_nil inline
    assert_equal "included", inline["inclusion"]
  end

  test "a duplicate roster row rolls back the whole add-players request" do
    sign_in_as(@owner)
    session_id = create_draft_session

    assert_no_difference("AssessmentSessionParticipant.count") do
      post_json "#{session_path(session_id)}/add_players", players: [
        { player_profile_id: @john.id },
        { player_profile_id: @john.id }
      ]
    end

    assert_response :unprocessable_entity
    assert_includes json["errors"].first["errors"].join(" "), "Player profile has already been taken"
  end

  test "the coach of record may remove a player from a draft roster" do
    sign_in_as(@owner)
    session_id = create_draft_session
    add_players!(session_id, [ { player_profile_id: @john.id } ])

    patch_json "#{session_path(session_id)}/remove_players",
               player_profile_ids: [ @john.id ]

    assert_response :success
    assert_equal 1, json["removed"]
    assert_equal [], json["assessment_session"]["participants"]
  end

  test "a published roster is frozen" do
    sign_in_as(@owner)

    assert_no_difference("AssessmentSessionParticipant.count") do
      patch_json "#{session_path(@published)}/remove_players",
                 player_profile_ids: [ @john.id ]
    end

    assert_response :unprocessable_entity
    assert_includes json["error"], "Only draft"
    assert_predicate @published.participants.reload, :any?
  end

  test "a non-owner coach cannot change the roster" do
    sign_in_as(@trainer)

    assert_no_difference("AssessmentSessionParticipant.count") do
      post_json "#{session_path(@draft)}/add_players",
                players: [ { player_profile_id: @pedro.id } ]
    end

    assert_response :forbidden
  end

  # --- score grid ------------------------------------------------------------

  test "saving a full grid creates draft results and the weighted total server-side" do
    sign_in_as(@owner)
    session_id = create_draft_session
    add_players!(session_id, [ { player_profile_id: @john.id } ])

    put_json "#{session_path(session_id)}/scores", scores: [
      { player_profile_id: @john.id, category_scores: category_cells([ 8, 7, 9 ]) }
    ]

    assert_response :success
    assessment = Assessment.find_by(
      assessment_session_id: session_id, player_profile_id: @john.id
    )
    assert_not_nil assessment
    assert_predicate assessment, :draft?, "session publish is the authority"
    assert_equal 80, assessment.score
    assert_equal 3, assessment.assessment_category_scores.count
    assert_equal [ 80, 70, 90 ],
                 assessment.assessment_category_scores
                          .includes(:assessment_category)
                          .sort_by { |row| row.assessment_category.position }
                          .map(&:score)

    result = json["assessment_session"]["participants"].first["result"]
    assert_equal "complete", result["status"]
    assert_equal 80, result["overall_score"]
    assert_equal 1, result["rank"]
  end

  test "an invalid cell rolls back every player's scores in the grid" do
    sign_in_as(@owner)
    session_id = create_draft_session
    add_players!(session_id, [
      { player_profile_id: @john.id },
      { player_profile_id: @pedro.id }
    ])

    assert_no_difference [ "Assessment.count", "AssessmentCategoryScore.count" ] do
      put_json "#{session_path(session_id)}/scores", scores: [
        { player_profile_id: @john.id, category_scores: category_cells([ 8, 7, 9 ]) },
        { player_profile_id: @pedro.id,
          category_scores: [
            { assessment_category_id: @definition.assessment_categories.order(:position).first.id,
              scale: "one_to_five", value: 9 }
          ] }
      ]
    end

    assert_response :unprocessable_entity
    assert_includes json["errors"].join(" "), "one_to_five"
  end

  test "a partial grid save leaves omitted categories incomplete, never zero" do
    sign_in_as(@owner)
    session_id = create_draft_session
    add_players!(session_id, [ { player_profile_id: @john.id } ])
    attack = @definition.assessment_categories.order(:position).first

    put_json "#{session_path(session_id)}/scores", scores: [
      { player_profile_id: @john.id,
        category_scores: [ { assessment_category_id: attack.id, scale: "one_to_ten", value: 8 } ] }
    ]

    assert_response :success
    assessment = Assessment.find_by(assessment_session_id: session_id)
    assert_equal 1, assessment.assessment_category_scores.count
    assert_nil assessment.score, "a partial set must not read as a partial total"

    result = json["assessment_session"]["participants"].first["result"]
    assert_equal "incomplete", result["status"]
    assert_nil result["overall_score"]
    assert_nil result["rank"]
    assert_equal 2, result["missing_category_ids"].size
  end

  test "scores are refused for off-roster and excluded players" do
    sign_in_as(@owner)
    session_id = create_draft_session

    put_json "#{session_path(session_id)}/scores", scores: [
      { player_profile_id: @john.id, category_scores: category_cells([ 8, 7, 9 ]) }
    ]
    assert_response :unprocessable_entity
    assert_includes json["errors"].join(" "), "not on this session roster"

    put_json "#{session_path(@draft)}/scores", scores: [
      { player_profile_id: @pedro.id, category_scores: category_cells([ 8, 7, 9 ]) }
    ]
    assert_response :unprocessable_entity
    assert_includes json["errors"].join(" "), "excluded"

    assert_no_difference("Assessment.count") do
      put_json "#{session_path(session_id)}/scores", scores: []
    end
    assert_response :unprocessable_entity
    assert_includes json["error"], "No scores"
  end

  test "a non-owner coach cannot save scores" do
    sign_in_as(@trainer)

    assert_no_difference("Assessment.count") do
      put_json "#{session_path(@draft)}/scores", scores: [
        { player_profile_id: @john.id, category_scores: category_cells([ 8, 7, 9 ]) }
      ]
    end

    assert_response :forbidden
  end

  # --- publish ---------------------------------------------------------------

  test "publish is gated on completeness and then cascades draft results in one step" do
    sign_in_as(@owner)
    session_id = create_draft_session
    add_players!(session_id, [ { player_profile_id: @john.id } ])

    post "#{session_path(session_id)}/publish"
    assert_response :unprocessable_entity
    assert_includes json["errors"].join(" "), "Score every included player"
    assert_equal "draft", AssessmentSession.find(session_id).status

    put_json "#{session_path(session_id)}/scores", scores: [
      { player_profile_id: @john.id, category_scores: category_cells([ 8, 7, 9 ]) }
    ]
    assert_response :success

    post "#{session_path(session_id)}/publish"
    assert_response :success
    session_record = AssessmentSession.find(session_id)
    assert_equal "published", session_record.status
    assert_not_nil session_record.published_at
    assessment = Assessment.find_by(assessment_session_id: session_id)
    assert_predicate assessment, :active?

    result = json["assessment_session"]["participants"].first["result"]
    assert_equal "complete", result["status"]
    assert_equal 80, result["overall_score"]

    # A published session is read-only, so the per-category entries behind that
    # total must be in the payload: a client cannot otherwise show how the score
    # was reached, and the grid would render permanently blank cells.
    cells = result["category_scores"].index_by { |c| c["assessment_category_id"] }
    expected = category_cells([ 8, 7, 9 ])
    assert_equal [ 8, 7, 9 ],
                 expected.map { |c| cells.fetch(c[:assessment_category_id])["reported_value"] }
    assert_equal 3, cells.size
    cells.each_value do |cell|
      assert_equal "one_to_ten", cell["scale"]
      assert_not_nil cell["score"]
    end
  end

  test "a published session refuses roster and score edits" do
    sign_in_as(@owner)
    session_id = create_draft_session
    add_players!(session_id, [ { player_profile_id: @john.id } ])
    put_json "#{session_path(session_id)}/scores", scores: [
      { player_profile_id: @john.id, category_scores: category_cells([ 8, 7, 9 ]) }
    ]
    assert_response :success
    post "#{session_path(session_id)}/publish"
    assert_response :success

    post_json "#{session_path(session_id)}/add_players",
              players: [ { player_profile_id: @pedro.id } ]
    assert_response :unprocessable_entity
    assert_includes json["error"], "Only draft"

    put_json "#{session_path(session_id)}/scores", scores: [
      { player_profile_id: @john.id, category_scores: category_cells([ 9, 9, 9 ]) }
    ]
    assert_response :unprocessable_entity
    assert_includes json["error"], "Only draft"
  end

  test "a non-owner coach cannot publish" do
    sign_in_as(@owner)
    session_id = create_draft_session
    add_players!(session_id, [ { player_profile_id: @john.id } ])
    put_json "#{session_path(session_id)}/scores", scores: [
      { player_profile_id: @john.id, category_scores: category_cells([ 8, 7, 9 ]) }
    ]
    assert_response :success

    sign_in_as(@trainer)
    post "#{session_path(session_id)}/publish"

    assert_response :forbidden
    assert_equal "draft", AssessmentSession.find(session_id).status
    assert_equal "draft", Assessment.find_by(assessment_session_id: session_id).status
  end

  # --- ranking ---------------------------------------------------------------

  test "ranking reports missing and excluded players without inventing zeroes" do
    sign_in_as(@owner)
    get "#{session_path(@draft)}/ranking"

    assert_response :success
    body = json
    assert_equal [], body["ranking"]
    assert_equal 1, body["incomplete"].size
    assert_equal @john.id, body["incomplete"].first["player_profile_id"]
    assert_equal "incomplete", body["incomplete"].first["status"]
    assert_equal 3, body["incomplete"].first["missing_category_ids"].size
    assert_equal 1, body["excluded"].size
    assert_equal @pedro.id, body["excluded"].first["player_profile_id"]
    assert_nil body["excluded"].first["overall_score"]
  end

  test "ranking uses standard competition ranking for ties" do
    sign_in_as(@owner)
    session_id = create_draft_session
    add_players!(session_id, [
      { player_profile_id: @john.id },
      { player_profile_id: @pedro.id }
    ])
    body = add_players!(session_id, [
      { person: { first_name: "Third", last_name: "Player" } }
    ])
    third_id = body["participants"].find { |row| row["player_name"] == "Third Player" }["player_profile_id"]

    put_json "#{session_path(session_id)}/scores", scores: [
      { player_profile_id: @john.id, category_scores: category_cells([ 8, 7, 9 ]) },
      { player_profile_id: @pedro.id, category_scores: category_cells([ 8, 7, 9 ]) },
      { player_profile_id: third_id, category_scores: category_cells([ 7, 6, 8 ]) }
    ]
    assert_response :success

    get "#{session_path(session_id)}/ranking"
    assert_response :success
    rows = json["ranking"]
    assert_equal 3, rows.size
    assert_equal [], json["incomplete"]

    ranks = rows.to_h { |row| [ row["player_profile_id"], row["rank"] ] }
    assert_equal 1, ranks[@john.id]
    assert_equal 1, ranks[@pedro.id]
    assert_equal 3, ranks[third_id]
    assert_not_includes ranks.values, 2
    assert_equal [ 80, 80, 70 ], rows.map { |row| row["overall_score"] }.sort.reverse
  end
end
