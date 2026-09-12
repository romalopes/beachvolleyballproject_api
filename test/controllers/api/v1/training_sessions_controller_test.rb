require "test_helper"

class Api::V1::TrainingSessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:two)    # coach + admin
    @coach = users(:three)  # coach role only
    @player = users(:one)   # player role only
    @drill = drills(:one)
    @owned = TrainingSession.create!(
      drill: @drill, scheduled_at: 1.day.from_now, location: "Beach", created_by: @coach
    )
  end

  test "index is public and includes drills" do
    get "/api/v1/training_sessions"
    assert_response :success
    body = JSON.parse(response.body)
    assert_kind_of Array, body
    assert body.first.key?("drill")
  end

  test "show is public and includes the drill" do
    session = training_sessions(:one)
    get "/api/v1/training_sessions/#{session.id}"
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal session.drill_id, body["drill"]["id"]
  end

  test "show returns 404 for an unknown id" do
    get "/api/v1/training_sessions/0"
    assert_response :not_found
    assert_equal "Training Session not found", JSON.parse(response.body)["error"]
  end

  test "coach can create a training session" do
    sign_in_as(@coach)
    assert_difference("TrainingSession.count") do
      post "/api/v1/training_sessions", params: { training_session: {
        drill_id: @drill.id, scheduled_at: 2.days.from_now.iso8601, location: "Court 1"
      } }
    end
    assert_response :created
    assert_equal @coach.id, TrainingSession.last.created_by_id
  end

  test "player cannot create a training session" do
    sign_in_as(@player)
    post "/api/v1/training_sessions", params: { training_session: {
      drill_id: @drill.id, scheduled_at: 2.days.from_now.iso8601
    } }
    assert_response :forbidden
  end

  test "guest cannot create a training session" do
    post "/api/v1/training_sessions", params: { training_session: {
      drill_id: @drill.id, scheduled_at: 2.days.from_now.iso8601
    } }
    assert_response :unauthorized
  end

  test "create returns 422 when scheduled_at is missing" do
    sign_in_as(@coach)
    post "/api/v1/training_sessions", params: { training_session: { drill_id: @drill.id } }
    assert_response :unprocessable_entity
    assert JSON.parse(response.body)["errors"].any?
  end

  test "owner can update their training session" do
    sign_in_as(@coach)
    patch "/api/v1/training_sessions/#{@owned.id}", params: { training_session: { location: "Court 2" } }
    assert_response :success
    assert_equal "Court 2", @owned.reload.location
  end

  test "non-owner cannot update another user's training session" do
    sign_in_as(@player)
    patch "/api/v1/training_sessions/#{@owned.id}", params: { training_session: { location: "Hacked" } }
    assert_response :forbidden
  end

  test "admin can update any training session" do
    sign_in_as(@admin)
    patch "/api/v1/training_sessions/#{@owned.id}", params: { training_session: { location: "Admin court" } }
    assert_response :success
    assert_equal "Admin court", @owned.reload.location
  end

  test "owner can destroy their training session" do
    sign_in_as(@coach)
    assert_difference("TrainingSession.count", -1) do
      delete "/api/v1/training_sessions/#{@owned.id}"
    end
    assert_response :no_content
  end

  test "guest cannot destroy a training session" do
    delete "/api/v1/training_sessions/#{@owned.id}"
    assert_response :unauthorized
    assert TrainingSession.exists?(@owned.id)
  end
end
