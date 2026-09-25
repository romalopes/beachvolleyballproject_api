require "test_helper"

# A configured category: exactly one source, a positive integer weight, and an
# order that is presentation-only.
class AssessmentCategoryTest < ActiveSupport::TestCase
  setup do
    @definition = assessment_definitions(:balanced)
    # `defense` is already configured on `balanced`, so these examples need a
    # category no definition has claimed yet.
    @free_category = categories(:two)
  end

  test "the rubric source is a category or a custom category, never both" do
    both = AssessmentCategory.new(
      assessment_definition: @definition,
      category: @free_category,
      category_custom: category_customs(:mental_game),
      weight: 10
    )
    assert_not both.valid?
    assert_includes both.errors.attribute_names, :category_custom

    neither = AssessmentCategory.new(assessment_definition: @definition, weight: 10)
    assert_not neither.valid?
    assert_includes neither.errors.attribute_names, :base
  end

  test "the database refuses a row with both sources" do
    assert_raises(ActiveRecord::StatementInvalid) do
      AssessmentCategory.insert!({
        assessment_definition_id: @definition.id,
        category_id: categories(:defense).id,
        category_custom_id: category_customs(:mental_game).id,
        weight: 10,
        position: 9,
        created_at: Time.current,
        updated_at: Time.current
      })
    end
  end

  test "weight must be a positive integer" do
    assert_not AssessmentCategory.new(assessment_definition: @definition, category: @free_category, weight: 0).valid?
    assert_not AssessmentCategory.new(assessment_definition: @definition, category: @free_category, weight: -5).valid?
    assert_not AssessmentCategory.new(assessment_definition: @definition, category: @free_category, weight: 12.5).valid?
    assert_not AssessmentCategory.new(assessment_definition: @definition, category: @free_category, weight: nil).valid?

    valid = AssessmentCategory.new(assessment_definition: @definition, category: @free_category, weight: 40)
    assert_predicate valid, :valid?, valid.errors.full_messages.to_sentence
  end

  test "position is a non-negative integer" do
    assert_not AssessmentCategory.new(assessment_definition: @definition, category: @free_category, weight: 10, position: -1).valid?

    valid = AssessmentCategory.new(assessment_definition: @definition, category: @free_category, weight: 10, position: 0)
    assert_predicate valid, :valid?
  end

  test "a client-supplied id must name a row that exists" do
    missing_category = AssessmentCategory.new(assessment_definition: @definition, category_id: 999_999, weight: 10)
    assert_not missing_category.valid?
    assert_includes missing_category.errors.attribute_names, :category

    missing_custom = AssessmentCategory.new(assessment_definition: @definition, category_custom_id: 999_999, weight: 10)
    assert_not missing_custom.valid?
    assert_includes missing_custom.errors.attribute_names, :category_custom
  end

  test "the row says which branch of the XOR it sits on and what to call it" do
    standard = assessment_categories(:balanced_attack)
    assert_equal "category", standard.source_type
    assert_equal "Attack", standard.label
    assert_not_predicate standard, :custom?

    custom = assessment_categories(:pre_season_mental)
    assert_equal "custom_category", custom.source_type
    assert_equal "Mental game", custom.label
    assert_predicate custom, :custom?
  end

  test "categories read in the configured order, not insertion order" do
    labels = @definition.assessment_categories.ordered.map(&:label)
    assert_equal %w[Attack Defense Serve], labels
  end

  test "metadata carries both branches for the API" do
    payload = assessment_categories(:balanced_defense).metadata

    assert_equal categories(:defense).id, payload[:category_id]
    assert_nil payload[:category_custom_id]
    assert_equal "category", payload[:source_type]
    assert_equal 30, payload[:weight]
    assert_equal "Defense", payload[:label]
    assert_equal "Defense", payload[:category][:name]

    custom_payload = assessment_categories(:pre_season_mental).metadata
    assert_equal "custom_category", custom_payload[:source_type]
    assert_equal "Mental game", custom_payload[:category_custom][:name]
    assert_nil custom_payload[:category]
  end
end
