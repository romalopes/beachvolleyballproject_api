require "test_helper"

class IdentityAssessmentCompatibilityTest < ActiveSupport::TestCase
  test "multiple player profiles keep distinct assessment histories through consolidation" do
    source = people(:accountless_player)
    canonical = Person.create!(first_name: "Assessment", last_name: "Canonical", creation_source: "system")
    first_profile = player_profiles(:pedro_player)
    second_profile = PlayerProfile.create!(person: source, status: "active", preferred_position: "setter")

    first_assessment = assessments(:skill_active)
    first_assessment.update!(player_profile: first_profile, notes: "First profile assessment")
    second_assessment = first_assessment.dup
    second_assessment.player_profile = second_profile
    second_assessment.notes = "Second profile assessment"
    second_assessment.save!

    snapshots = [first_assessment, second_assessment].index_by(&:id).transform_values do |assessment|
      assessment.attributes.slice(
        "id", "player_profile_id", "coach_profile_id", "score", "reported_value",
        "scale", "status", "created_at", "updated_at", "notes"
      )
    end
    coach_profile_id = coach_profiles(:maria_coach).id

    PersonConsolidationService.execute!(source_person: source, canonical_person: canonical,
                                         performed_by: users(:two))

    assert_equal [first_profile.id, second_profile.id].sort,
                 PlayerProfile.where(person_id: canonical.id).pluck(:id).sort
    [first_assessment.id, second_assessment.id].each do |id|
      assessment = Assessment.find(id)
      assert_equal snapshots.fetch(id), assessment.attributes.slice(*snapshots.fetch(id).keys)
      assert_equal coach_profile_id, assessment.coach_profile_id
      assert_equal canonical.id, assessment.player_profile.person_id
    end
  end
end
