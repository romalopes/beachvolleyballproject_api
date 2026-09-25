require "test_helper"

# A custom category exists to make "who may use this?" answerable — which is
# the whole reason it became a record instead of the free-text column it was.
class CategoryCustomTest < ActiveSupport::TestCase
  setup do
    @coach = users(:three)     # coach, creator of the private row
    @other_coach = users(:six) # coach, creator of the shared row
    @admin = users(:two)
    @curator = users(:four)
    @player = users(:one)
  end

  test "the shared row is usable by any content creator" do
    shared = category_customs(:mental_game)

    assert_predicate shared, :shared?
    assert shared.usable_by?(@coach)
    assert shared.usable_by?(@other_coach)
    assert shared.usable_by?(@admin)
    assert shared.usable_by?(@curator)
  end

  test "a private row is usable by its creator and oversight only" do
    private_row = category_customs(:private_rubric)

    assert_predicate private_row, :private?
    assert private_row.usable_by?(@coach), "the creator may use it"
    assert private_row.usable_by?(@admin), "oversight may use it"
    assert private_row.usable_by?(@curator), "oversight may use it"
    assert_not private_row.usable_by?(@other_coach), "another coach may not"
    assert_not private_row.usable_by?(@player)
    assert_not private_row.usable_by?(nil)
  end

  test "only the author and oversight may manage the record" do
    row = category_customs(:private_rubric)

    assert row.manageable_by?(@coach)
    assert row.manageable_by?(@admin)
    assert row.manageable_by?(@curator)
    assert_not row.manageable_by?(@other_coach)
    assert_not row.manageable_by?(nil)
  end

  test "name is required and unique per creator" do
    blank = CategoryCustom.new(name: "  ", visibility: "shared")
    assert_not blank.valid?
    assert_includes blank.errors.attribute_names, :name

    duplicate = CategoryCustom.new(
      name: category_customs(:mental_game).name,
      created_by: @other_coach,
      visibility: "shared"
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors.attribute_names, :name

    # A different coach may record the same words for their own catalogue.
    other = CategoryCustom.new(name: "Mental game", created_by: @coach, visibility: "shared")
    assert other.valid?, other.errors.full_messages.to_sentence
  end

  test "blank custom text becomes NULL, never an empty string" do
    row = CategoryCustom.new(name: "   ")
    row.valid?
    assert_nil row.name
  end

  test "visibility must be shared or private" do
    row = CategoryCustom.new(name: "Court sense", visibility: "everyone")
    assert_not row.valid?
    assert_includes row.errors.attribute_names, :visibility
  end

  test "an in-use custom category is refused rather than deleted" do
    # `mental_game` is quoted by the pre-season definition's configuration.
    row = category_customs(:mental_game)

    assert_not row.destroy
    assert row.persisted?
    assert CategoryCustom.exists?(row.id)
  end
end
