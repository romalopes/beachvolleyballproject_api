require "test_helper"

class Api::V1::CoachesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @public_user = users(:one)   # player role only
    @trainer = users(:three)     # coach role only
    @admin = users(:two)         # coach + admin
    @curator = users(:four)      # curator: manages trainings, not content
  end

  test "index returns all active coaches" do
    sign_in_as(@admin)
    get api_v1_coaches_path
    assert_response :success
    body = JSON.parse(response.body)
    assert_kind_of Array, body["data"]
    assert body["data"].any? { |c| c["person"]["first_name"] == "Maria" }
  end

  test "index paginates 20 per page by default" do
    sign_in_as(@admin)
    22.times do |index|
      Person.create!(first_name: "Coach#{format('%02d', index)}", last_name: "Zzz",
                     creation_source: "system").create_coach_profile!
    end

    get api_v1_coaches_path
    body = JSON.parse(response.body)
    assert_equal 20, body["data"].length
    assert_equal 1, body["meta"]["page"]
    assert_equal 20, body["meta"]["per_page"]
    assert_equal 23, body["meta"]["total"]
    assert_equal 2, body["meta"]["total_pages"]

    get api_v1_coaches_path, params: { page: 2 }
    second = JSON.parse(response.body)
    assert_equal 3, second["data"].length
    assert_equal [], body["data"].map { |c| c["id"] } & second["data"].map { |c| c["id"] },
                 "pages must not overlap"
  end

  test "index filters by name search" do
    sign_in_as(@admin)
    get api_v1_coaches_path, params: { q: "Maria" }
    assert_response :success
    body = JSON.parse(response.body)
    assert body["data"].all? { |c| c["full_name"].downcase.include?("maria") }
  end

  test "index filters by email" do
    sign_in_as(@admin)
    get api_v1_coaches_path, params: { email: "two@example.com" }
    assert_response :success
    body = JSON.parse(response.body)
    assert body["data"].all? { |c| c["person"]["email"] == "two@example.com" }
  end

  test "show returns coach detail" do
    coach = coach_profiles(:maria_coach)
    sign_in_as(@admin)
    get api_v1_coach_path(coach)
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal coach.id, body["id"]
    assert_equal "Maria", body["person"]["first_name"]
  end

  test "show returns 404 for missing coach" do
    sign_in_as(@admin)
    get api_v1_coach_path(99999)
    assert_response :not_found
  end

  test "create coach requires coach or admin role" do
    sign_in_as(@public_user)
    post api_v1_coaches_path, params: coach_create_params
    assert_response :forbidden
  end

  test "create coach as coach" do
    sign_in_as(@trainer)

    post api_v1_coaches_path, params: coach_create_params

    assert_response :created
    body = JSON.parse(response.body)
    assert_kind_of Integer, body["id"]
    assert_equal "New", body["person"]["first_name"]
    assert body["coach_profile_id"].present?
    assert_equal "active", body["status"]
  end

  test "create returns validation errors" do
    sign_in_as(@admin)
    post api_v1_coaches_path, params: {
      coach: { person: { first_name: "" }, coach_profile: { coaching_level: "t olympic" } }
    }
    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_kind_of Array, body["errors"]
  end

  test "create coach with profile attributes" do
    sign_in_as(@admin)
    count_before = CoachProfile.count
    post api_v1_coaches_path, params: {
      coach: {
        person: { first_name: "NewCoach2", last_name: "User" },
        coach_profile: { coaching_level: "national", qualifications: "USVTT cert" }
      }
    }
    assert_response :created
    assert_equal count_before + 1, CoachProfile.count
  end

  test "index requires a training manager" do
    sign_in_as(@public_user)
    get api_v1_coaches_path
    assert_response :forbidden

    sign_out
    sign_in_as(@curator)
    get api_v1_coaches_path
    assert_response :success
  end

  test "create coach links an existing person instead of creating one" do
    sign_in_as(@admin)
    person = Person.create!(first_name: "Linkable", last_name: "Coach", creation_source: "system")
    people_before = Person.count

    post api_v1_coaches_path, params: {
      coach: { person_id: person.id, coach_profile: { coaching_level: "state" } }
    }

    assert_response :created
    body = JSON.parse(response.body)
    assert_equal person.id, body["person_id"]
    assert_equal people_before, Person.count, "no new person should be recorded"
    assert_equal "system", person.reload.creation_source, "linking must not rewrite provenance"
  end

  test "create coach reports possible duplicates as suggestions only" do
    sign_in_as(@admin)
    existing = Person.create!(first_name: "Existing", last_name: "Coach", email: "dup_coach@example.com",
                              creation_source: "signup")

    post api_v1_coaches_path, params: {
      coach: { person: { first_name: "Another", last_name: "Person", email: "DUP_COACH@example.com" },
               coach_profile: { coaching_level: "state" } }
    }

    assert_response :created
    body = JSON.parse(response.body)
    duplicate_ids = body["possible_duplicates"].map { |duplicate| duplicate["id"] }

    assert_includes duplicate_ids, existing.id
    assert_not_includes duplicate_ids, body["person"]["id"], "a person is never its own duplicate"
    assert_nil existing.reload.merged_into_id, "duplicates are never merged automatically"
  end

  test "create coach marks staff-recorded provenance" do
    sign_in_as(@admin)

    post api_v1_coaches_path, params: coach_create_params

    assert_response :created
    body = JSON.parse(response.body)
    assert_equal "coach_created", body["person"]["creation_source"]
    assert_equal @admin.id, Person.find(body["person"]["id"]).created_by_id
  end

  test "update coach changes profile and person attributes" do
    sign_in_as(@admin)
    coach = coach_profiles(:maria_coach)

    patch api_v1_coach_path(coach), params: {
      coach: {
        coach_profile: { coaching_level: "national", qualifications: "Level 3" },
        person: { email: "coach_one@example.com" }
      }
    }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "national", body["coaching_level"]
    assert_equal "coach_one@example.com", body["person"]["email"]
    assert_equal "national", coach.reload.coaching_level
    assert_equal coach.person_id, body["person"]["id"], "the person is updated, not replaced"
  end

  test "update coach requires a content creator" do
    coach = coach_profiles(:maria_coach)

    sign_in_as(@curator)
    patch api_v1_coach_path(coach), params: { coach: { coach_profile: { coaching_level: "national" } } }

    assert_response :forbidden
    assert_not_equal "national", coach.reload.coaching_level
  end

  test "update coach records the previous name as an alias" do
    sign_in_as(@admin)
    coach = coach_profiles(:maria_coach)
    previous_name = coach.person.full_name

    patch api_v1_coach_path(coach), params: { coach: { person: { first_name: "Renamed" } } }

    assert_response :success
    assert_equal [ previous_name ], coach.person.reload.person_aliases.pluck(:full_name)
  end

  test "update coach returns validation errors" do
    sign_in_as(@admin)

    patch api_v1_coach_path(coach_profiles(:maria_coach)), params: { coach: { person: { first_name: "" } } }

    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body)["errors"], "Person first name can't be blank"
  end

  test "update coach returns 404 for an unknown coach" do
    sign_in_as(@admin)

    patch api_v1_coach_path(0), params: { coach: { coach_profile: { coaching_level: "national" } } }

    assert_response :not_found
  end

  test "index hides archived coaches by default and lists them on request" do
    sign_in_as(@admin)
    coach = coach_profiles(:maria_coach)
    coach.update!(status: "archived")

    get api_v1_coaches_path
    assert_equal [], JSON.parse(response.body)["data"].map { |c| c["id"] }

    get api_v1_coaches_path, params: { status: "archived" }
    assert_equal [ coach.id ], JSON.parse(response.body)["data"].map { |c| c["id"] }
  end

  test "index rejects an unknown status filter" do
    sign_in_as(@admin)

    get api_v1_coaches_path, params: { status: "retired" }

    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body)["errors"], "status is not included in the list"
  end

  test "an archived coach can be restored" do
    sign_in_as(@admin)
    coach = coach_profiles(:maria_coach)
    coach.update!(status: "archived")

    patch api_v1_coach_path(coach), params: { coach: { coach_profile: { status: "active" } } }

    assert_response :success
    assert_equal "active", coach.reload.status
  end

  test "there is no hard delete for a coach" do
    sign_in_as(@admin)
    coach = coach_profiles(:maria_coach)

    delete "/api/v1/coaches/#{coach.id}"

    assert_response :not_found
    assert CoachProfile.exists?(coach.id)
  end

  private

  def coach_create_params
    { coach: {
      person: { first_name: "New", last_name: "Coach", email: "new_coach_created@example.com" },
      coach_profile: { coaching_level: "state", qualifications: "Level 1" }
    } }
  end
end
