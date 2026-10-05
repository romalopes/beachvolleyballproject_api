require "test_helper"

class Api::V1::PersonConsolidationsControllerTest < ActionDispatch::IntegrationTest
  test "preview and create require an administrator" do
    params = { person_consolidation: { source_person_id: people(:accountless_player).id,
                                       canonical_person_id: people(:club_officer).id } }
    post preview_api_v1_person_consolidations_path, params: params
    assert_response :unauthorized

    sign_in_as(users(:one))
    post preview_api_v1_person_consolidations_path, params: params
    assert_response :forbidden
    post api_v1_person_consolidations_path, params: params
    assert_response :forbidden
  end

  test "admin can preview without mutating and create an audited consolidation" do
    sign_in_as(users(:two))
    source = people(:accountless_player)
    canonical = Person.create!(first_name: "API", last_name: "Canonical", creation_source: "system")
    params = { person_consolidation: { source_person_id: source.id, canonical_person_id: canonical.id } }

    post preview_api_v1_person_consolidations_path, params: params
    assert_response :success
    assert_equal true, JSON.parse(response.body)["ready"]
    assert_equal "active", source.reload.status
    assert_equal 0, PersonConsolidation.where(source_person_id: source.id).count

    post api_v1_person_consolidations_path, params: params
    assert_response :created
    body = JSON.parse(response.body)
    audit = PersonConsolidation.find(body.fetch("id"))
    assert_equal source.id, audit.source_person_id
    assert_equal users(:two).id, audit.performed_by_id

    get api_v1_person_consolidation_path(audit)
    assert_response :success
    assert_equal audit.id, JSON.parse(response.body)["id"]
  end

  test "admin receives conflict preview and no partial consolidation" do
    sign_in_as(users(:two))
    source = people(:one)
    canonical = people(:two)

    post api_v1_person_consolidations_path, params: {
      person_consolidation: { source_person_id: source.id, canonical_person_id: canonical.id }
    }

    assert_response :conflict
    assert_includes JSON.parse(response.body).dig("preview", "conflicts").map { |item| item["type"] }, "account_conflict"
    assert_equal "active", source.reload.status
    assert_empty PersonConsolidation.where(source_person_id: source.id)
  end

  test "explicit membership resolution is admin-only and audited" do
    source = people(:accountless_player)
    canonical = Person.create!(first_name: "Resolution", last_name: "Target", creation_source: "system")
    canonical_membership = OrganisationMembership.create!(
      organisation: organisations(:sydney_club), person: canonical, role: "member", status: "active"
    )
    conflict = PersonConsolidationService.preview(source_person: source, canonical_person: canonical)[:conflicts].first
    params = {
      person_consolidation: { source_person_id: source.id, canonical_person_id: canonical.id },
      membership_resolutions: [
        { type: conflict[:type], container_id: conflict[:container_id],
          keep_record_id: conflict[:source_record_id], reason: "Verified against the current club roster" }
      ]
    }

    sign_in_as(users(:one))
    post resolve_api_v1_person_consolidations_path, params: params
    assert_response :forbidden

    sign_in_as(users(:two))
    post resolve_api_v1_person_consolidations_path, params: params

    assert_response :created
    body = JSON.parse(response.body)
    audit = PersonConsolidation.find(body.fetch("id"))
    resolution = audit.result.fetch("membership_resolutions").first
    assert_equal canonical_membership.id, resolution.fetch("discarded_record_id")
    assert_equal "Verified against the current club roster", resolution.fetch("reason")
    assert_equal canonical.id, organisation_memberships(:accountless_club_member).reload.person_id
    assert_not OrganisationMembership.exists?(id: canonical_membership.id)
  end
end
