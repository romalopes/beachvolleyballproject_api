require "test_helper"

class Api::V1::AssessmentDefinitionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @owner = users(:six)      # coach: authored the `balanced` fixture
    @trainer = users(:three)  # coach who owns nothing
    @admin = users(:two)      # oversight + content creator
    @curator = users(:four)   # oversight, but NOT a content creator
    @player_user = users(:one)
    @balanced = assessment_definitions(:balanced)
    @pre_season = assessment_definitions(:pre_season)
  end

  # --- index / show ----------------------------------------------------------

  test "index requires authentication" do
    get api_v1_assessment_definitions_path
    assert_response :unauthorized
  end

  test "index refuses a player-role user" do
    sign_in_as(@player_user)
    get api_v1_assessment_definitions_path
    assert_response :forbidden
  end

  test "index returns the pagination envelope with the configuration" do
    sign_in_as(@trainer)
    get api_v1_assessment_definitions_path

    assert_response :success
    body = JSON.parse(response.body)
    assert_kind_of Array, body["data"]
    assert body["meta"]["total"].present?

    balanced = body["data"].find { |row| row["id"] == @balanced.id }
    assert_equal "A-Level Assessment", balanced["name"]
    assert_equal "active", balanced["status"]
    assert_equal 100, balanced["total_weight"]
    assert balanced["weights_balanced"]
    assert_equal %w[Attack Defense Serve],
                 balanced["assessment_categories"].map { |row| row["label"] }
    assert_equal [40, 30, 30], balanced["assessment_categories"].map { |row| row["weight"] }
  end

  test "index narrows with the status filter" do
    sign_in_as(@trainer)
    get api_v1_assessment_definitions_path, params: { status: "draft" }

    ids = JSON.parse(response.body)["data"].map { |row| row["id"] }
    assert_equal [ @pre_season.id ], ids
  end

  test "show returns a definition to any training manager" do
    sign_in_as(@trainer)
    get api_v1_assessment_definition_path(@pre_season)

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 80, body["total_weight"]
    assert_equal 20, body["remaining_weight"]
    assert_equal [ "Attack", "Mental game" ],
                 body["assessment_categories"].map { |row| row["label"] }
    assert_equal [ "category", "custom_category" ],
                 body["assessment_categories"].map { |row| row["source_type"] }
  end

  test "show returns 404 for an unknown id" do
    sign_in_as(@admin)
    get api_v1_assessment_definition_path(id: AssessmentDefinition.order(:id).last.id + 1)

    assert_response :not_found
  end

  # --- create ----------------------------------------------------------------

  test "create stores the configuration and fills positions from the array order" do
    sign_in_as(@owner)
    assert_difference -> { AssessmentDefinition.count }, 1 do
      post api_v1_assessment_definitions_path, params: {
        assessment_definition: {
          name: "Two-area trial",
          status: "draft",
          assessment_categories_attributes: [
            { category_id: categories(:defense).id, weight: 60 },
            { category_id: categories(:serve).id, weight: 40 }
          ]
        }
      }, as: :json
    end

    assert_response :created
    body = JSON.parse(response.body)
    assert_equal @owner.id, body["created_by"]["id"]
    assert_equal [0, 1], body["assessment_categories"].map { |row| row["position"] }
    assert_equal 100, body["total_weight"]
    assert body["weights_balanced"]
  end

  test "create refuses a curator, who is oversight but records no content" do
    sign_in_as(@curator)
    post api_v1_assessment_definitions_path, params: {
      assessment_definition: { name: "Nope", assessment_categories_attributes: [] }
    }, as: :json

    assert_response :forbidden
  end

  test "create refuses to activate an unbalanced definition, naming the total" do
    sign_in_as(@owner)
    post api_v1_assessment_definitions_path, params: {
      assessment_definition: {
        name: "Half built",
        status: "active",
        assessment_categories_attributes: [ { category_id: categories(:defense).id, weight: 70 } ]
      }
    }, as: :json

    assert_response :unprocessable_entity
    message = JSON.parse(response.body)["errors"].join(" ")
    assert_includes message, "must total 100%"
    assert_includes message, "Current total: 70%."
  end

  test "create refuses the same category twice even under load" do
    sign_in_as(@owner)
    post api_v1_assessment_definitions_path, params: {
      assessment_definition: {
        name: "Duplicated",
        assessment_categories_attributes: [
          { category_id: categories(:defense).id, weight: 50 },
          { category_id: categories(:defense).id, weight: 50 }
        ]
      }
    }, as: :json

    assert_response :unprocessable_entity
  end

  # --- update ----------------------------------------------------------------

  test "the author may edit an unused definition" do
    sign_in_as(@owner)
    patch api_v1_assessment_definition_path(@pre_season), params: {
      assessment_definition: { name: "Screening v2" }
    }, as: :json

    assert_response :success
    assert_equal "Screening v2", @pre_season.reload.name
  end

  test "another coach may not edit a definition they did not author" do
    sign_in_as(@trainer)
    patch api_v1_assessment_definition_path(@balanced), params: {
      assessment_definition: { name: "Tampered" }
    }, as: :json

    assert_response :forbidden
    assert_equal "A-Level Assessment", @balanced.reload.name
  end

  test "oversight may edit somebody else's definition" do
    sign_in_as(@admin)
    patch api_v1_assessment_definition_path(@pre_season), params: {
      assessment_definition: { name: "Screening (curated)" }
    }, as: :json

    assert_response :success
    assert_equal "Screening (curated)", @pre_season.reload.name
  end

  test "an in-use definition is frozen: reconfiguration is 422, naming the way out" do
    freeze_with_result
    sign_in_as(@owner)

    patch api_v1_assessment_definition_path(@balanced), params: {
      assessment_definition: {
        name: "Renamed",
        assessment_categories_attributes: [ { id: assessment_categories(:balanced_serve).id, weight: 25 } ]
      }
    }, as: :json

    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body)["errors"].join(" "), "duplicate it to make changes"
    assert_equal "A-Level Assessment", @balanced.reload.name
    assert_equal 30, assessment_categories(:balanced_serve).reload.weight
  end

  test "an in-use definition may still be archived" do
    freeze_with_result
    sign_in_as(@owner)

    patch api_v1_assessment_definition_path(@balanced), params: {
      assessment_definition: { status: "archived" }
    }, as: :json

    assert_response :success
    assert_equal "archived", @balanced.reload.status
  end

  # --- reorder ---------------------------------------------------------------

  test "reorder rewrites positions and nothing about the weights" do
    sign_in_as(@owner)
    ids = @balanced.assessment_categories.ordered.map(&:id).reverse

    patch reorder_api_v1_assessment_definition_path(@balanced), params: { ids: ids }, as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal ids, body["assessment_categories"].map { |row| row["id"] }
    assert_equal [0, 1, 2], body["assessment_categories"].map { |row| row["position"] }
    assert_equal %w[Serve Defense Attack],
                 body["assessment_categories"].map { |row| row["label"] }
    # Weights travel with their category, not with the position — reversing the
    # order therefore reverses the weight list too, and the total still holds.
    assert_equal [30, 30, 40], body["assessment_categories"].map { |row| row["weight"] }
    assert_equal 100, body["total_weight"]
  end

  test "reorder must list every category exactly once" do
    sign_in_as(@owner)
    patch reorder_api_v1_assessment_definition_path(@balanced),
          params: { ids: [ assessment_categories(:balanced_attack).id ] }, as: :json

    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body)["errors"].join(" "), "exactly once"
  end

  test "reorder is refused on an in-use definition" do
    freeze_with_result
    sign_in_as(@owner)
    ids = @balanced.assessment_categories.ordered.map(&:id)

    patch reorder_api_v1_assessment_definition_path(@balanced), params: { ids: ids }, as: :json

    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body)["errors"].join(" "), "duplicate it to make changes"
  end

  test "reorder is forbidden to a coach who is not the author" do
    sign_in_as(@trainer)
    patch reorder_api_v1_assessment_definition_path(@balanced),
          params: { ids: @balanced.assessment_categories.ordered.map(&:id) }, as: :json

    assert_response :forbidden
  end

  # --- retirement: archive (soft) and destroy (hard) ---------------------------
  #
  # Two tiers, because "no longer wanted" and "never existed" are different
  # requests. Archiving is reversible and never blocked by usage; a hard delete is
  # admin-only and refused while anything points at the definition.

  test "an admin archives a definition without destroying it" do
    sign_in_as(@admin)

    post archive_api_v1_assessment_definition_path(@pre_season)

    assert_response :success
    assert_equal "archived", JSON.parse(response.body)["status"]
    # Soft delete: the row is still there, and so are its categories.
    assert_predicate AssessmentDefinition.find(@pre_season.id), :archived?
    assert_equal @pre_season.assessment_categories.count,
                 @pre_season.reload.assessment_categories.count
  end

  test "an admin restores an archived definition to draft" do
    sign_in_as(@admin)
    @pre_season.update!(status: "archived")

    post restore_api_v1_assessment_definition_path(@pre_season)

    assert_response :success
    # Draft, not `active`: weights may have drifted, and `active` demands a
    # balanced total, so draft is the state that cannot be wrong.
    assert_equal "draft", JSON.parse(response.body)["status"]
  end

  test "archiving is refused when already archived, and restoring a live one" do
    sign_in_as(@admin)
    @pre_season.update!(status: "archived")

    post archive_api_v1_assessment_definition_path(@pre_season)
    assert_response :unprocessable_entity
    assert_match(/already archived/, JSON.parse(response.body)["errors"].join(" "))

    @pre_season.update!(status: "draft")
    post restore_api_v1_assessment_definition_path(@pre_season)
    assert_response :unprocessable_entity
    assert_match(/not archived/, JSON.parse(response.body)["errors"].join(" "))
  end

  test "a definition in use may be archived but not deleted" do
    sign_in_as(@admin)
    freeze_with_result

    # Archiving stays available: hiding a configuration people still score against
    # is a legitimate request, and unlike deleting it loses nothing.
    post archive_api_v1_assessment_definition_path(@balanced)
    assert_response :success

    delete api_v1_assessment_definition_path(@balanced)

    assert_response :unprocessable_entity
    assert_match(/in use by .*assessment/, JSON.parse(response.body)["errors"].join(" "))
    assert_match(/archive it instead/i, JSON.parse(response.body)["errors"].join(" "))
    assert_predicate AssessmentDefinition.find(@balanced.id), :archived?
  end

  test "a session alone is enough to block a hard delete" do
    # No results recorded, but a session quotes the definition — deleting it would
    # leave a session pointing at a configuration that no longer exists. `@balanced`
    # is already active and balanced, so a session may legitimately be built on it.
    sign_in_as(@admin)
    AssessmentSession.create!(
      name: "Uses it", assessment_definition: @balanced,
      coach_profile: coach_profiles(:maria_coach), created_by: @admin,
      status: "published", published_at: Time.current, scheduled_on: Date.current
    )

    delete api_v1_assessment_definition_path(@balanced)

    assert_response :unprocessable_entity
    assert_match(/assessment session/, JSON.parse(response.body)["errors"].join(" "))
    assert_predicate AssessmentDefinition.find(@balanced.id), :persisted?
  end

  test "a published ranking alone is enough to block a hard delete" do
    sign_in_as(@admin)
    used = AssessmentDefinition.create!(name: "Ranking-only", status: "draft", created_by: @admin)
    RankingConsolidation.create!(assessment_definition: used, created_by: @admin)

    delete api_v1_assessment_definition_path(used)

    assert_response :unprocessable_entity
    assert_match(/ranking consolidation/, JSON.parse(response.body)["errors"].join(" "))
  end

  test "an admin hard deletes an unused definition and its categories" do
    sign_in_as(@admin)
    category = @pre_season.assessment_categories.first
    assert category.present?

    delete api_v1_assessment_definition_path(@pre_season)

    assert_response :success
    assert_not AssessmentDefinition.exists?(@pre_season.id)
    # Categories are owned by the definition, so they go with it — that is the
    # difference between deleting an unused definition and archiving a used one.
    assert_nil AssessmentCategory.find_by(id: category.id)
  end

  test "the definition author may not archive or delete it" do
    sign_in_as(@owner)

    post archive_api_v1_assessment_definition_path(@pre_season)
    assert_response :forbidden

    delete api_v1_assessment_definition_path(@pre_season)
    assert_response :forbidden
    assert_predicate AssessmentDefinition.find(@pre_season.id), :draft?
  end

  test "a curator may not archive or delete, being oversight but not an admin" do
    sign_in_as(@curator)

    post archive_api_v1_assessment_definition_path(@pre_season)
    assert_response :forbidden

    delete api_v1_assessment_definition_path(@pre_season)
    assert_response :forbidden
  end

  test "a coach and a guest may not archive or delete" do
    sign_in_as(@trainer)
    post archive_api_v1_assessment_definition_path(@pre_season)
    assert_response :forbidden

    sign_out
    delete api_v1_assessment_definition_path(@pre_season)
    assert_response :unauthorized
  end

  test "the payload says what blocks a delete instead of only offering the button" do
    sign_in_as(@trainer)
    freeze_with_result

    get api_v1_assessment_definition_path(@balanced)

    assert_response :success
    body = JSON.parse(response.body)
    assert body["in_use"]
    assert_not body["deletable"]
    assert body["usage_counts"]["assessments"].positive?
    assert_match(/assessment/, body["usage_summary"])
    # Archiving is offered even though the delete is not.
    assert body["archivable"]
  end

  private

  # Quote the definition with a result, which is what freezes it. Built inline
  # so no assessment fixture shifts the Phase 4 counts the existing controller
  # tests pin.
  def freeze_with_result
    person = Person.create!(first_name: "Frozen", last_name: "Case", creation_source: "system")
    profile = person.create_player_profile!
    other_person = Person.create!(first_name: "Frozen", last_name: "Coach", creation_source: "system")
    coach = other_person.create_coach_profile!

    Assessment.create!(
      player_profile: profile,
      coach_profile: coach,
      created_by: @owner,
      assessment_definition: @balanced,
      status: "draft"
    )
    @balanced.reload
  end
end
