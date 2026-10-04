require "test_helper"

# Regression test for the 500 ("no implicit conversion of String into Integer")
# that a nested `organisation_memberships_attributes` PATCH used to raise: strong
# parameters unwrap the nested hash one level, so the controller has to assign
# Rails the row array, not the wrapper hash.
class NestedMembershipsReproTest < ActionDispatch::IntegrationTest
  test "a coach PATCH with nested memberships saves the rows" do
    coach_user = users(:six)   # owns maria_coach
    club = organisations(:sydney_club)
    other = organisations(:volleyball_nsw)

    # A fresh person, so fixture memberships cannot collide with the rows this
    # test creates.
    person = Person.create!(first_name: "Nested", last_name: "Repro",
                            creation_source: "coach_created", created_by: coach_user)
    profile = CoachProfile.create!(person: person, created_by: coach_user)
    OrganisationMembership.create!(organisation: other, person: coach_user.person,
                                   role: "administrator", status: "active")

    # Start from one existing membership so the payload mixes an update and a create.
    existing = person.organisation_memberships.create!(
      organisation: club, role: "coach", status: "active"
    )

    sign_in_as(coach_user)
    patch "/api/v1/coaches/#{profile.id}",
          params: {
            coach: {
              person: {
                first_name: person.first_name,
                last_name: person.last_name,
                email: person.email,
                phone: nil,
                organisation_memberships_attributes: [
                  { id: existing.id, organisation_id: club.id, role: "coach", status: "active" },
                  { organisation_id: other.id, role: "member", status: "pending" }
                ]
              },
              coach_profile: { coaching_level: nil, qualifications: nil, visibility: "shared" }
            }
          }.to_json,
          headers: { "Content-Type" => "application/json" }

    assert_response :success, "#{response.status}: #{response.body}"
    rows = person.reload.organisation_memberships.order(:id)
    assert_equal 2, rows.count
    assert_equal [ club.id, other.id ], rows.map(&:organisation_id)
    assert_equal %w[coach member], rows.map(&:role)
  end

  test "a content creator cannot grant themselves roster control through nested person attributes" do
    coach_user = users(:three)
    club = organisations(:sydney_club)
    sign_in_as(coach_user)

    assert_not coach_user.person.member_of?(club)
    assert_no_difference ["Person.count", "OrganisationMembership.count"] do
      post "/api/v1/people",
           params: {
             person: {
               first_name: "Forged",
               last_name: "Officer",
               organisation_memberships_attributes: [
                 { organisation_id: club.id, role: "owner", status: "active" }
               ]
             }
           }.to_json,
           headers: { "Content-Type" => "application/json" }
    end

    assert_response :forbidden
    assert_match(/owner or administrator/, JSON.parse(response.body)["errors"].first)
  end
end
