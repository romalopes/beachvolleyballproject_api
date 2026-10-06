require "test_helper"

# Request tests for the identity search used by the "create player/coach" flow.
#
# The endpoint answers "has this human already been recorded?" before a new
# Person is created, so it exposes contact details and is therefore staff-only
# (coaches/admins — the same people who may create profiles).
class Api::V1::PeopleControllerTest < ActionDispatch::IntegrationTest
  setup do
    @public_user = users(:one)   # player role only
    @trainer = users(:three)     # coach role only
    @admin = users(:two)         # coach + admin
    @curator = users(:four)      # curator: manages trainings, not content
  end

  test "index lists canonical people with account status and profile ids" do
    sign_in_as(@admin)
    get search_api_v1_people_path

    assert_response :success
    body = JSON.parse(response.body)

    john = body.find { |person| person["id"] == people(:one).id }
    assert_equal "John Smith", john["full_name"]
    assert_equal "connected", john["account_status"]
    assert_equal player_profiles(:john_player).id, john["player_profile_id"]
    assert_nil john["coach_profile_id"]

    pedro = body.find { |person| person["id"] == people(:accountless_player).id }
    assert_equal "profile_only", pedro["account_status"]
    assert_equal player_profiles(:pedro_player).id, pedro["player_profile_id"]
  end

  test "index excludes merged people" do
    sign_in_as(@admin)
    get search_api_v1_people_path

    ids = JSON.parse(response.body).map { |person| person["id"] }
    assert_not_includes ids, people(:merged).id
  end

  test "index orders people by last name then first name" do
    sign_in_as(@admin)
    get search_api_v1_people_path

    keys = JSON.parse(response.body).map { |p| [ p["last_name"].to_s, p["first_name"].to_s, p["id"] ] }
    assert_equal keys.sort, keys
  end

  test "index searches by name or email" do
    sign_in_as(@admin)
    get search_api_v1_people_path, params: { q: "Pedro" }

    assert_response :success
    names = JSON.parse(response.body).map { |person| person["full_name"] }
    assert_equal [ "Pedro Santos" ], names

    get search_api_v1_people_path, params: { q: "one@example.com" }
    emails = JSON.parse(response.body).map { |person| person["email"] }
    assert_includes emails, "one@example.com"
  end

  test "index filters by exact email" do
    sign_in_as(@admin)
    get search_api_v1_people_path, params: { email: "ONE@example.com" }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal [ people(:one).id ], body.map { |person| person["id"] }
  end

  test "index finds a person by a previous name" do
    sign_in_as(@admin)

    get search_api_v1_people_path, params: { q: "Johnny" }

    assert_response :success
    ids = JSON.parse(response.body).map { |person| person["id"] }
    assert_equal [ people(:one).id ], ids
  end

  test "index returns the alternate names with each person" do
    sign_in_as(@admin)

    get search_api_v1_people_path, params: { q: "one@example.com" }

    body = JSON.parse(response.body)
    assert_equal %w[Johnny\ Smith João\ Smith].sort, body.first["aliases"].sort
  end

  test "index is limited so it cannot dump the whole people table" do
    sign_in_as(@admin)
    (Api::V1::PeopleController::LIMIT + 5).times do |index|
      Person.create!(first_name: "Person#{index}", last_name: "Zzz", creation_source: "system")
    end

    get search_api_v1_people_path

    assert_response :success
    assert_equal Api::V1::PeopleController::LIMIT, JSON.parse(response.body).length
  end

  test "index requires a content creator" do
    [ @public_user, @curator ].each do |viewer|
      sign_in_as(viewer)
      get search_api_v1_people_path
      assert_response :forbidden
    end
  end

  test "index requires authentication" do
    get search_api_v1_people_path
    assert_response :unauthorized
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

  # --- the paginated management list -----------------------------------------

  test "the management list returns the pagination envelope" do
    sign_in_as(@trainer)

    get api_v1_people_path

    assert_response :success
    body = JSON.parse(response.body)
    assert body["data"].is_a?(Array)
    assert_equal 20, body["meta"]["per_page"]
    assert_operator body["meta"]["total"], :>, 0
  end

  test "the management list narrows with the same search as the typeahead" do
    sign_in_as(@trainer)

    get api_v1_people_path, params: { q: "Pedro" }

    assert_response :success
    names = JSON.parse(response.body)["data"].map { |p| p["full_name"] }
    assert names.any? { |n| n.include?("Pedro") }
  end

  test "the management list excludes merged people" do
    sign_in_as(@trainer)

    get api_v1_people_path, params: { per_page: 100 }

    ids = JSON.parse(response.body)["data"].map { |p| p["id"] }
    assert_not_includes ids, people(:merged).id
  end

  # --- create / update --------------------------------------------------------

  test "a coach may record a person, and the provenance is the server's" do
    sign_in_as(@trainer)

    post_json api_v1_people_path,
              person: { first_name: "Rosa", last_name: "New", email: "rosa@example.com" }

    assert_response :created
    person = Person.find_by(email: "rosa@example.com")
    assert_equal "coach_created", person.creation_source
    assert_equal @trainer, person.created_by
  end

  test "a caller cannot forge the provenance of a new person" do
    sign_in_as(@trainer)

    post_json api_v1_people_path, person: { first_name: "Forged", creation_source: "signup" }

    assert_response :created
    assert_equal "coach_created", Person.find_by(first_name: "Forged").creation_source
  end

  test "create refuses a person with no name" do
    sign_in_as(@trainer)

    post_json api_v1_people_path, person: { first_name: "" }

    assert_response :unprocessable_entity
  end

  test "a coach may correct a person's details" do
    sign_in_as(@trainer)

    patch_json "/api/v1/people/#{people(:one).id}",
               person: { last_name: "Renamed", phone: "0400000000" }

    assert_response :success
    assert_equal "Renamed", people(:one).reload.last_name
  end

  test "update does not let a caller rewrite provenance" do
    sign_in_as(@trainer)
    before_source = people(:one).creation_source

    patch_json "/api/v1/people/#{people(:one).id}", person: { creation_source: "signup" }

    assert_response :success
    assert_equal before_source, people(:one).reload.creation_source
  end

  test "show returns 404 for an unknown person" do
    sign_in_as(@trainer)

    get "/api/v1/people/0"

    assert_response :not_found
  end

  # --- delete: admin only ----------------------------------------------------

  test "a coach may not delete a person" do
    sign_in_as(@trainer)

    delete "/api/v1/people/#{people(:one).id}"

    assert_response :forbidden
    assert Person.exists?(people(:one).id)
  end

  test "a curator may not delete a person, being oversight but not administration" do
    sign_in_as(@curator)

    delete "/api/v1/people/#{people(:one).id}"

    assert_response :forbidden
  end

  test "an admin may delete a person" do
    sign_in_as(@admin)
    person = Person.create!(first_name: "Mistake", last_name: "Record",
                            creation_source: "system")

    delete "/api/v1/people/#{person.id}"

    assert_response :success
    assert_not Person.exists?(person.id)
  end

  test "a person with an account cannot be deleted, so the account is not orphaned" do
    sign_in_as(@admin)
    # `people(:five)` does not exist: the person behind an account is `people(:one)`.
    person = people(:one)
    assert person.player_profiles.exists?(account_id: accounts(:one).id), "the fixture must have an Account-linked profile for this test to mean anything"

    delete "/api/v1/people/#{person.id}"

    # `dependent: :restrict_with_error` on the account: a refusal, not a silently
    # detached login.
    assert_response :unprocessable_entity
    assert Person.exists?(person.id)
  end

  # The refusal is correct; what was wrong was the *wording*. These cover the
  # message an admin actually reads, which is the part that was unusable.
  test "a refusal explains the block in domain language rather than leaking a table name" do
    sign_in_as(@admin)
    person = Person.create!(first_name: "Refused", last_name: "Record", creation_source: "system")
    CoachProfile.create!(person: person, created_by: @admin)

    delete "/api/v1/people/#{person.id}"

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal "This person cannot be deleted.", body["error"]
    assert_includes body["reasons"], "They have a coach profile."
    assert_includes body["details"], "Archive the coach profile instead of deleting it — it holds the coaching history."

    # The old message named the database table; a user-facing message must not.
    serialized = response.body
    assert_not_includes serialized, "coach_profiles"
    assert_not_includes serialized, "Cannot delete record because dependent"
    assert Person.exists?(person.id)
  end

  test "the refusal is reported before any write, so nothing is rolled back" do
    sign_in_as(@admin)
    person = people(:one) # has an account
    assert_difference -> { person.reload.updated_at }, 0 do
      delete "/api/v1/people/#{person.id}"
    end
    assert_response :unprocessable_entity
  end

  test "every blocking reason is listed at once rather than one per attempt" do
    sign_in_as(@admin)
    person = people(:one) # account + profiles
    assert_operator person.player_profiles.count + person.coach_profiles.count, :>=, 1

    delete "/api/v1/people/#{person.id}"

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_includes body["reasons"], "They are signed in as an account."
    assert_operator body["reasons"].size, :>=, 2
  end

  test "a person with no blocking relations deletes cleanly" do
    sign_in_as(@admin)
    person = Person.create!(first_name: "Deletable", last_name: "Record", creation_source: "system")

    delete "/api/v1/people/#{person.id}"

    assert_response :success
    assert_not Person.exists?(person.id)
  end

  # --- promotion: admin only -------------------------------------------------

  test "an admin may turn a person into a player" do
    sign_in_as(@admin)
    person = Person.create!(first_name: "Wannabe", last_name: "Player",
                            creation_source: "system")
    assert_nil person.player_profile

    post "/api/v1/people/#{person.id}/promote", params: { promotion: { role: "player" } }

    assert_response :created
    assert person.reload.player_profile
    assert_equal "player", json["profile_kind"]
  end

  test "an admin may turn a person into a coach" do
    sign_in_as(@admin)
    person = Person.create!(first_name: "Wannabe", last_name: "Coach",
                            creation_source: "system")

    post "/api/v1/people/#{person.id}/promote", params: { promotion: { role: "coach" } }

    assert_response :created
    assert person.reload.coach_profile
  end

  test "promotion is admin-only, because it is not the same as creating a player" do
    # A coach may create a brand-new player every day. Attaching a profile to an
    # identity that may already be on a roster, with assessments attributed to it,
    # is a different and broader act.
    sign_in_as(@trainer)
    person = Person.create!(first_name: "Wannabe", last_name: "Player",
                            creation_source: "system")

    post "/api/v1/people/#{person.id}/promote", params: { promotion: { role: "player" } }

    assert_response :forbidden
    assert_nil person.reload.player_profile
  end

  test "promoting somebody who is already a player creates another profile" do
    sign_in_as(@admin)
    person = people(:one)
    existing = person.player_profile
    assert existing

    post "/api/v1/people/#{person.id}/promote", params: { promotion: { role: "player" } }

    assert_response :created
    assert_equal 2, person.reload.player_profiles.count
    assert_equal existing.id, person.reload.player_profile.id
  end

  test "an unknown promotion role is refused" do
    sign_in_as(@admin)
    person = Person.create!(first_name: "Wannabe", last_name: "Player",
                            creation_source: "system")

    post "/api/v1/people/#{person.id}/promote", params: { promotion: { role: "admin" } }

    assert_response :unprocessable_entity
    assert_nil person.reload.player_profile
  end
end
