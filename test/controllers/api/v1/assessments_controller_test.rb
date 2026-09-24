require "test_helper"

class Api::V1::AssessmentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @trainer = users(:three)     # coach role, owns nothing, no coach profile
    @assessor = users(:six)      # coach role, coach profile maria_coach
    @admin = users(:two)         # coach + admin (oversight AND content creator)
    @curator = users(:four)      # curator: oversight, but NOT a content creator
    @player_user = users(:one)   # player role only
  end

  # --- index -----------------------------------------------------------------

  test "index requires authentication" do
    get api_v1_assessments_path
    assert_response :unauthorized
  end

  test "index refuses a player-role user" do
    sign_in_as(@player_user)
    get api_v1_assessments_path
    assert_response :forbidden
  end

  test "index defaults to published rows and the pagination envelope" do
    sign_in_as(@admin)
    get api_v1_assessments_path

    assert_response :success
    body = JSON.parse(response.body)
    assert_kind_of Array, body["data"]
    assert body["meta"]["total"].present?
    # Oversight sees everything, but the default status is `active` — only one
    # fixture row is published, and drafts/withdrawn are not club knowledge.
    assert_equal [ assessments(:skill_active).id ], body["data"].map { |row| row["id"] }
  end

  test "index keeps the active default even for a stakeholder, whose status filter reaches their drafts" do
    sign_in_as(@assessor)
    get api_v1_assessments_path

    assert_equal 1, JSON.parse(response.body)["meta"]["total"] # the published row only

    get api_v1_assessments_path, params: { status: "draft", mine: "1" }
    ids = JSON.parse(response.body)["data"].map { |row| row["id"] }
    assert_equal [ assessments(:draft_ready).id, assessments(:draft_assigned).id ].sort, ids.sort
  end

  test "index scoped by the player filter" do
    sign_in_as(@admin)
    get api_v1_assessments_path, params: { player_id: player_profiles(:pedro_player).id }

    ids = JSON.parse(response.body)["data"].map { |row| row["id"] }
    assert_includes ids, assessments(:skill_active).id
    assert_not_includes ids, assessments(:custom_withdrawn).id # john's row
  end

  test "index narrows with coach, skill and session filters" do
    sign_in_as(@admin)
    get api_v1_assessments_path, params: {
      coach_id: coach_profiles(:maria_coach).id,
      skill_id: skills(:assessment_rubric).id,
      training_session_id: training_sessions(:one).id
    }

    assert_equal [ assessments(:skill_active).id ],
                 JSON.parse(response.body)["data"].map { |row| row["id"] }
  end

  test "index status filter replaces the active default" do
    sign_in_as(@assessor)
    get api_v1_assessments_path, params: { status: "draft" }

    ids = JSON.parse(response.body)["data"].map { |row| row["id"] }
    assert_equal [ assessments(:draft_ready).id, assessments(:draft_assigned).id ].sort, ids.sort
  end

  test "index rejects an invalid status filter" do
    sign_in_as(@admin)
    get api_v1_assessments_path, params: { status: "secret" }

    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body)["errors"].join, "status"
  end

  test "index mine narrows to rows I recorded or am attributed in" do
    sign_in_as(@trainer) # a coach who recorded nothing and assesses nobody
    get api_v1_assessments_path, params: { status: "draft", mine: "1" }

    assert_equal 0, JSON.parse(response.body)["meta"]["total"]
  end

  # --- show ------------------------------------------------------------------

  test "show returns a published row to any training manager" do
    sign_in_as(@trainer)
    get api_v1_assessment_path(assessments(:skill_active))

    assert_response :success
    row = JSON.parse(response.body)
    assert_equal assessments(:skill_active).id, row["id"]
    assert_equal 70, row["score"]
    assert_equal 4, row["reported_value"]
    assert_equal "one_to_five", row["scale"]
    assert_equal 7, row["ten_scale"]
    assert_equal 4, row["five_scale"]
    assert_equal "Coach Six", row["created_by"]["name"]
    assert_equal "Forearm pass", row["skill"]["title"]
  end

  test "show returns a draft to its stakeholder" do
    sign_in_as(@assessor)
    get api_v1_assessment_path(assessments(:draft_ready))

    assert_response :success
  end

  test "show returns 404 — not 403 — for a row that does not exist for the caller" do
    sign_in_as(@trainer) # not a stakeholder of the withdrawn row
    get api_v1_assessment_path(assessments(:custom_withdrawn))

    assert_response :not_found
  end

  test "show returns 404 for an unknown id" do
    sign_in_as(@admin)
    get api_v1_assessment_path(id: Assessment.order(:id).last.id + 1)

    assert_response :not_found
  end

  # --- create ----------------------------------------------------------------

  test "create converts the coach's own entry to the canonical score" do
    sign_in_as(@assessor)
    assert_difference -> { Assessment.count }, 1 do
      post api_v1_assessments_path, params: {
        assessment: {
          player_profile_id: player_profiles(:pedro_player).id,
          skill_id: skills(:assessment_rubric).id,
          value: 4,
          scale: "one_to_five",
          status: "active",
          notes: "Reads the serve well."
        }
      }
    end

    assert_response :created
    row = JSON.parse(response.body)
    assert_equal 70, row["score"]
    assert_equal 4, row["reported_value"]
    assert_equal @assessor.id, row["created_by"]["id"]
    assert_equal coach_profiles(:maria_coach).id, row["coach_profile_id"]
  end

  test "create defaults to draft status" do
    sign_in_as(@assessor)
    post api_v1_assessments_path, params: {
      assessment: {
        player_profile_id: player_profiles(:john_player).id,
        custom_skill: "Blocking calls",
        value: 3
      }
    }

    assert_response :created
    row = JSON.parse(response.body)
    assert_equal "draft", row["status"]
    assert_equal "one_to_ten", row["scale"] # the default scale
    # The rubric XOR: a custom row serializes with an explicit nil skill.
    assert_nil row["skill"]
    assert_equal "Blocking calls", row["custom_skill"]
  end

  test "create accepts a canonical score and backfills the reported value" do
    sign_in_as(@assessor)
    post api_v1_assessments_path, params: {
      assessment: {
        player_profile_id: player_profiles(:john_player).id,
        custom_skill: "Serve placement",
        score: 70,
        scale: "one_to_five"
      }
    }

    assert_response :created
    row = JSON.parse(response.body)
    assert_equal 70, row["score"]
    assert_equal 4, row["reported_value"]
  end

  test "create rejects a value that does not exist on the scale" do
    sign_in_as(@assessor)
    post api_v1_assessments_path, params: {
      assessment: {
        player_profile_id: player_profiles(:john_player).id,
        custom_skill: "Serve placement",
        value: 6,
        scale: "one_to_five"
      }
    }

    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body)["errors"].join, "one_to_five"
  end

  test "create refuses a coach attributing the row to another coach" do
    other_coach = create_coach_profile
    sign_in_as(@assessor)

    post api_v1_assessments_path, params: {
      assessment: {
        player_profile_id: player_profiles(:john_player).id,
        custom_skill: "Serve placement",
        value: 3,
        coach_profile_id: other_coach.id
      }
    }

    assert_response :forbidden
    assert_equal [ "You may only record assessments as yourself" ], JSON.parse(response.body)["errors"]
  end

  test "create lets oversight record on behalf of another coach" do
    other_coach = create_coach_profile
    sign_in_as(@admin)

    post api_v1_assessments_path, params: {
      assessment: {
        player_profile_id: player_profiles(:john_player).id,
        custom_skill: "Serve placement",
        value: 3,
        coach_profile_id: other_coach.id
      }
    }

    assert_response :created
    assert_equal other_coach.id, JSON.parse(response.body)["coach_profile_id"]
  end

  test "create requires a content creator" do
    sign_in_as(@curator) # oversight, but curators record no content
    post api_v1_assessments_path, params: {
      assessment: {
        player_profile_id: player_profiles(:john_player).id,
        custom_skill: "Serve placement",
        value: 3
      }
    }

    assert_response :forbidden
  end

  test "create refuses a coach assessing their own player profile" do
    dual_player = PlayerProfile.create!(person: people(:two), visibility: "shared")
    sign_in_as(@assessor) # maria_coach belongs to the same person

    post api_v1_assessments_path, params: {
      assessment: {
        player_profile_id: dual_player.id,
        custom_skill: "Serve placement",
        value: 3
      }
    }

    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body)["errors"].join, "same person"
  end

  # --- update ----------------------------------------------------------------

  test "update re-scores the row from a new value" do
    sign_in_as(@assessor)
    patch api_v1_assessment_path(assessments(:skill_active)), params: {
      assessment: { value: 3, scale: "one_to_five" }
    }

    assert_response :success
    row = JSON.parse(response.body)
    assert_equal RatingScale.to_score(3, scale: "one_to_five"), row["score"]
    assert_equal 3, row["reported_value"]
  end

  test "update publishes a rated draft" do
    sign_in_as(@assessor)
    patch api_v1_assessment_path(assessments(:draft_ready)), params: {
      assessment: { status: "active" }
    }

    assert_response :success
    assert_equal "active", JSON.parse(response.body)["status"]
  end

  test "update refuses to publish an unrated draft" do
    sign_in_as(@assessor)
    patch api_v1_assessment_path(assessments(:draft_assigned)), params: {
      assessment: { status: "active" }
    }

    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body)["errors"].join, "Score"
  end

  test "update refuses to re-point the row at another player" do
    sign_in_as(@assessor)
    patch api_v1_assessment_path(assessments(:skill_active)), params: {
      assessment: { player_profile_id: player_profiles(:john_player).id }
    }

    assert_response :unprocessable_entity
    assert_equal assessments(:skill_active).reload.player_profile_id, player_profiles(:pedro_player).id
  end

  test "update is forbidden to a coach who is not a stakeholder" do
    sign_in_as(@trainer)
    patch api_v1_assessment_path(assessments(:skill_active)), params: {
      assessment: { notes: "Tampered." }
    }

    assert_response :forbidden
    assert_equal "Consistent platform; late on short serves.",
                 assessments(:skill_active).reload.notes
  end

  test "update lets oversight edit any row" do
    sign_in_as(@curator)
    patch api_v1_assessment_path(assessments(:skill_active)), params: {
      assessment: { notes: "Corrected by oversight." }
    }

    assert_response :success
    assert_equal "Corrected by oversight.", assessments(:skill_active).reload.notes
  end

  # --- destroy is deliberately absent (D18) ----------------------------------

  test "delete is a 404: nothing in this project is hard-deleted" do
    sign_in_as(@admin)
    delete api_v1_assessment_path(assessments(:skill_active))

    assert_response :not_found
    assert_predicate assessments(:skill_active).reload, :present?
  end

  private

  # A second coach profile for the attribution tests, built inline so the
  # fixture cast stays exactly as the plan pins it.
  def create_coach_profile
    person = Person.create!(first_name: "Second", last_name: "Coach",
                            creation_source: "coach_created", created_by: @admin)
    CoachProfile.create!(person: person, visibility: "shared", created_by: @admin)
  end
end
