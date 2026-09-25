require "test_helper"

# The rules that make a definition a *configuration* rather than a list: the
# weights balance before it may be used, and once results quote it, it is
# history (edit by duplicating, retire by archiving, never by deleting).
class AssessmentDefinitionTest < ActiveSupport::TestCase
  setup do
    @owner = users(:six)
    @other_coach = users(:three)
    @admin = users(:two)
    @curator = users(:four)
    @balanced = assessment_definitions(:balanced)
    @pre_season = assessment_definitions(:pre_season)
  end

  test "the balanced definition totals 100 and the draft does not" do
    assert_equal 100, @balanced.total_weight
    assert_predicate @balanced, :weights_balanced?
    assert_equal 0, @balanced.remaining_weight

    assert_equal 80, @pre_season.total_weight
    assert_not_predicate @pre_season, :weights_balanced?
    assert_equal 20, @pre_season.remaining_weight
  end

  test "a draft may be unbalanced while it is being built" do
    assert_predicate @pre_season, :draft?
    assert_predicate @pre_season, :valid?
  end

  test "activating an unbalanced definition is refused, naming the number" do
    @pre_season.status = "active"

    assert_not @pre_season.valid?
    message = @pre_season.errors.full_messages.join(" ")
    assert_includes message, "must total 100%"
    assert_includes message, "Current total: 80%."
  end

  test "activating a balanced definition is allowed" do
    @balanced.status = "archived"
    assert_predicate @balanced, :valid?

    @balanced.status = "active"
    assert_predicate @balanced, :valid?
  end

  test "status must be one of draft, active or archived" do
    definition = AssessmentDefinition.new(name: "Whatever", status: "retired")
    assert_not definition.valid?
    assert_includes definition.errors.attribute_names, :status
  end

  test "name is required" do
    definition = AssessmentDefinition.new(name: "   ")
    assert_not definition.valid?
    assert_includes definition.errors.attribute_names, :name
  end

  test "the same category may not be configured twice" do
    duplicate = AssessmentCategory.new(
      assessment_definition: @balanced,
      category: categories(:assessment_rubric),
      weight: 10,
      position: 9
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors.attribute_names, :category_id
  end

  test "the same custom category may not be configured twice" do
    duplicate = AssessmentCategory.new(
      assessment_definition: @pre_season,
      category_custom: category_customs(:mental_game),
      weight: 10,
      position: 9
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors.attribute_names, :category_custom_id
  end

  test "the database refuses a duplicate source even when validation is skipped" do
    assert_raises(ActiveRecord::RecordNotUnique) do
      AssessmentCategory.insert!({
        assessment_definition_id: @balanced.id,
        category_id: categories(:assessment_rubric).id,
        weight: 10,
        position: 9,
        created_at: Time.current,
        updated_at: Time.current
      })
    end
  end

  # --- D7: a definition that results point at is frozen -----------------------

  test "an in-use definition may not be renamed" do
    freeze_with_result

    @balanced.name = "Renamed"
    assert_not @balanced.valid?
    assert_includes @balanced.errors.full_messages.join(" "), "duplicate it to make changes"
  end

  test "an in-use definition may not have its category set changed" do
    freeze_with_result

    @balanced.assessment_categories_attributes = [
      { id: assessment_categories(:balanced_serve).id, weight: 25 }
    ]

    assert_not @balanced.valid?
    assert_includes @balanced.errors.full_messages.join(" "), "duplicate it to make changes"
  end

  test "an in-use definition may still be archived" do
    freeze_with_result

    @balanced.status = "archived"
    assert_predicate @balanced, :valid?
    assert @balanced.save
    assert_predicate @balanced.reload, :archived?
  end

  test "an unused definition may be renamed and destroyed with its configuration" do
    @pre_season.name = "Screening v2"
    assert_predicate @pre_season, :valid?

    assert_difference -> { AssessmentCategory.count }, -2 do
      assert @pre_season.destroy
    end
  end

  test "a definition is never destroyed while results quote it" do
    freeze_with_result

    assert_not @balanced.destroy
    assert AssessmentDefinition.exists?(@balanced.id)
  end

  test "metadata carries the configuration the SPA renders" do
    payload = @balanced.metadata

    assert_equal "A-Level Assessment", payload[:name]
    assert_equal 100, payload[:total_weight]
    assert payload[:weights_balanced]
    assert_not payload[:referenced]
    assert_equal %w[Attack Defense Serve], payload[:assessment_categories].map { |row| row[:label] }
    assert_equal [40, 30, 30], payload[:assessment_categories].map { |row| row[:weight] }
    assert_equal [0, 1, 2], payload[:assessment_categories].map { |row| row[:position] }
  end

  private

  # Give the fixture definition a result, which is what freezes it. Built inline
  # on purpose: no assessment fixture may change the Phase 4 counts the
  # existing controller tests pin.
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
