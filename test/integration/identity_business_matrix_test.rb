require "test_helper"

class IdentityBusinessMatrixTest < ActionDispatch::IntegrationTest
  test "claim discovery, review, and approval link the existing profile without rewriting assessment history" do
    OrganisationMembership.find_or_create_by!(
      person: users(:three).person, organisation: organisations(:sydney_club)
    ) do |membership|
      membership.role = "coach"
      membership.status = "active"
      membership.joined_at = Time.current
    end
    profile = PlayerProfile.create!(display_name: "John Smith", created_by: users(:three))
    assessment = assessments(:draft_ready)
    assessment.update!(player_profile: profile)
    assessment_id = assessment.id
    assessment_snapshot = assessment.reload.attributes.slice(
      "id", "player_profile_id", "coach_profile_id", "score", "reported_value",
      "scale", "status", "created_at", "updated_at", "notes"
    )
    people_before = Person.count

    sign_in_as(users(:five))
    get candidates_api_v1_player_claims_path
    assert_response :success
    assert_includes JSON.parse(response.body).map { |row| row["player_profile_id"] }, profile.id

    post api_v1_player_claims_path, params: { player_profile_id: profile.id }
    assert_response :created
    claim_id = JSON.parse(response.body).fetch("id")
    assert_nil profile.reload.person_id

    sign_in_as(users(:three))
    post approve_api_v1_player_claim_path(claim_id)

    assert_response :success
    assert_equal "approved", PlayerClaim.find(claim_id).status
    assert_equal people(:one).id, profile.reload.person_id
    assert_equal profile.id, PlayerClaim.find(claim_id).player_profile_key
    assert_equal assessment_snapshot, Assessment.find(assessment_id).attributes.slice(*assessment_snapshot.keys)
    assert_equal people_before, Person.count
  end

  test "a person with multiple coach profiles can attribute an assessment to the selected profile" do
    person = people(:two)
    original_profile_id = coach_profiles(:maria_coach).id
    account_id = person.account.id
    player_profile_ids = person.player_profiles.order(:id).pluck(:id)
    membership_ids = person.organisation_memberships.order(:id).pluck(:id)

    sign_in_as(users(:six))
    post api_v1_coaches_path, params: {
      coach: { person_id: person.id, coach_profile: { coaching_level: "advanced", qualifications: "Matrix profile" } }
    }

    assert_response :created
    second_profile_id = JSON.parse(response.body).fetch("id")
    assert_not_equal original_profile_id, second_profile_id
    assert_equal [ original_profile_id, second_profile_id ].sort, person.reload.coach_profiles.order(:id).pluck(:id).sort
    assert_equal account_id, person.account.id
    assert_equal player_profile_ids, person.player_profiles.order(:id).pluck(:id)
    assert_equal membership_ids, person.organisation_memberships.order(:id).pluck(:id)

    post api_v1_assessments_path, params: {
      assessment: {
        player_profile_id: player_profiles(:pedro_player).id,
        custom_category: "Profile attribution matrix",
        value: 4,
        coach_profile_id: second_profile_id
      }
    }

    assert_response :created
    assessment = Assessment.find(JSON.parse(response.body).fetch("id"))
    assert_equal player_profiles(:pedro_player).id, assessment.player_profile_id
    assert_equal second_profile_id, assessment.coach_profile_id
    assert_equal person.id, assessment.coach_profile.person_id
  end

  test "admin consolidation preserves profile, assessment, membership, group, and alias record ids" do
    source = people(:accountless_player)
    canonical = Person.create!(first_name: "Matrix", last_name: "Canonical", creation_source: "system")
    source_coach = CoachProfile.create!(person: source, coaching_level: "level_1")
    assessment = assessments(:skill_active)
    assessment.update!(player_profile: player_profiles(:john_player), coach_profile: source_coach)
    assessment_id = assessment.id
    assessment_snapshot = assessment.reload.attributes.slice(
      "id", "player_profile_id", "coach_profile_id", "score", "reported_value",
      "scale", "status", "created_at", "updated_at", "notes"
    )
    player_profile_id = player_profiles(:pedro_player).id
    organisation_membership_id = organisation_memberships(:accountless_club_member).id
    group_membership_id = group_memberships(:u19_squad_pedro).id
    alias_record = source.person_aliases.create!(full_name: "Matrix Source Alias", alias_type: "nickname")

    sign_in_as(users(:two))
    post api_v1_person_consolidations_path, params: {
      person_consolidation: { source_person_id: source.id, canonical_person_id: canonical.id }
    }

    assert_response :created
    audit = PersonConsolidation.find(JSON.parse(response.body).fetch("id"))
    assert_equal source.id, audit.source_person_id
    assert_equal canonical.id, audit.canonical_person_id
    assert_equal users(:two).id, audit.performed_by_id
    assert_equal "merged", source.reload.status
    assert_equal canonical.id, PlayerProfile.find(player_profile_id).person_id
    assert_equal canonical.id, source_coach.reload.person_id
    assert_equal canonical.id, OrganisationMembership.find(organisation_membership_id).person_id
    assert_equal canonical.id, GroupMembership.find(group_membership_id).person_id
    assert_equal canonical.id, PersonAlias.find(alias_record.id).person_id
    assert_equal assessment_snapshot, Assessment.find(assessment_id).attributes.slice(*assessment_snapshot.keys)
  end
end
