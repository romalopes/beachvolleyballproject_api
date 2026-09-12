require "test_helper"

class Api::V1::HealthControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:two)    # coach + admin
    @player = users(:one)   # player role only
  end

  test "liveness is public and returns ok" do
    get "/api/v1/health"
    assert_response :success
    assert_equal({ "status" => "ok" }, JSON.parse(response.body))
  end

  test "liveness does not leak version, environment or stack details" do
    get "/api/v1/health"
    assert_equal ["status"], JSON.parse(response.body).keys
  end

  test "liveness returns 503 when the database connection fails" do
    with_db_down do
      get "/api/v1/health"
    end
    assert_response :service_unavailable
    assert_equal({ "status" => "error" }, JSON.parse(response.body))
  end

  test "detailed requires authentication" do
    get "/api/v1/health/detailed"
    assert_response :unauthorized
  end

  test "detailed rejects a non-admin user" do
    sign_in_as(@player)
    get "/api/v1/health/detailed"
    assert_response :forbidden
    assert_equal "Forbidden", JSON.parse(response.body)["error"]
  end

  test "detailed accepts an admin bearer token" do
    session = @admin.sessions.create!(
      api_token: SecureRandom.hex(32),
      api_token_expires_at: 30.days.from_now
    )
    get "/api/v1/health/detailed", headers: { "Authorization" => "Bearer #{session.api_token}" }
    assert_response :success
    assert_equal "ok", JSON.parse(response.body)["status"]
  end

  test "detailed returns the diagnostic payload as admin" do
    sign_in_as(@admin)
    get "/api/v1/health/detailed"
    assert_response :success
    body = JSON.parse(response.body)

    assert_equal "ok", body["status"]
    assert_equal "bvb-api", body["service"]
    assert_equal "ok", body["database"]
    assert_equal Rails.env, body["environment"]
    assert_equal BACK_END_VERSION, body["version"]
    assert body["timestamp"].present?

    db = body["database_details"]
    assert_kind_of Hash, db
    assert_includes db.keys, "adapter"
    assert_includes db.keys, "pool"
    assert_match(/postgres/i, db["adapter"].to_s)
    assert_kind_of Integer, db["pool"]

    server = body["server"]
    assert_kind_of Hash, server
    %w[rails_version ruby puma_workers hostname pid].each do |key|
      assert_includes server.keys, key
    end
    assert_kind_of Integer, server["pid"]

    endpoint = body["endpoint"]
    assert_kind_of Hash, endpoint
    assert_equal "/api/v1/health/detailed", endpoint["path"]
    assert endpoint["base_url"].start_with?("http")
  end

  test "detailed reports record counts for the SPA domain resources" do
    sign_in_as(@admin)
    get "/api/v1/health/detailed"
    assert_response :success
    counts = JSON.parse(response.body)["counts"]
    assert_kind_of Hash, counts
    %w[categories skills drills drill_skills media_assets training_sessions users].each do |key|
      assert_kind_of Integer, counts[key], "expected integer count for #{key}"
    end
    assert_operator counts["categories"], :>=, 1
    assert_operator counts["users"], :>=, 1
  end

  test "detailed returns 503 with nil-safe db details when the database is down" do
    sign_in_as(@admin)
    with_db_down(break_config: true) do
      get "/api/v1/health/detailed"
    end
    assert_response :service_unavailable
    body = JSON.parse(response.body)
    assert_equal "error", body["status"]
    assert_equal "error", body["database"]
    assert_kind_of Hash, body["database_details"]
    assert_nil body["database_details"]["adapter"]
    assert_kind_of Hash, body["server"]
    assert_kind_of Hash, body["endpoint"]
    assert_kind_of Hash, body["counts"]
  end

  private

  # Simulates a database outage without extra stubbing gems: temporarily
  # replaces the connection's #active? (and optionally the config lookup)
  # via singleton methods, then restores them.
  def with_db_down(break_config: false)
    connection = ActiveRecord::Base.connection
    connection.define_singleton_method(:active?) { false }
    config_owner = nil
    if break_config
      config_owner = ActiveRecord::Base.singleton_class
      config_owner.send(:alias_method, :__health_orig_db_config, :connection_db_config)
      config_owner.send(:define_method, :connection_db_config) { |*| raise StandardError, "boom" }
    end
    yield
  ensure
    connection.singleton_class.send(:remove_method, :active?)
    if break_config && config_owner
      config_owner.send(:alias_method, :connection_db_config, :__health_orig_db_config)
      config_owner.send(:remove_method, :__health_orig_db_config)
    end
  end
end
