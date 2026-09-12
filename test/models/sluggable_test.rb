require "test_helper"

class SluggableTest < ActiveSupport::TestCase
  test "generates a slug from the title on create" do
    skill = Skill.create!(title: "Jump Serve", category: categories(:one))
    assert_equal "jump-serve", skill.slug
  end

  test "generates a unique slug when the base is taken" do
    first = Skill.create!(title: "Unique Title Here", category: categories(:one))
    second = Skill.create!(title: "Unique Title Here", category: categories(:two))
    assert_equal "unique-title-here", first.slug
    assert_equal "unique-title-here-2", second.slug
  end

  test "regenerates the slug when the source column changes" do
    skill = skills(:one)
    skill.update!(title: "Completely New Title")
    assert_equal "completely-new-title", skill.reload.slug
  end

  test "keeps the slug when unrelated attributes change" do
    skill = skills(:one)
    original = skill.slug
    skill.update!(description: "Only the description changed")
    assert_equal original, skill.reload.slug
  end

  test "falls back to a default slug when the title has no URL-safe characters" do
    category = Category.create!(name: "!!!")
    assert_equal "item", category.slug
  end

  test "keeps slugs unique for duplicates with the same base" do
    first = Skill.create!(title: "Beach Defense", category: categories(:one))
    second = Skill.create!(title: "Beach Defense", category: categories(:two))
    assert_equal "beach-defense", first.slug
    assert_equal "beach-defense-2", second.slug
  end

  test "drills generate slugs from their title" do
    drill = Drill.create!(
      title: "Side Out Race",
      training_stage: "middle",
      difficulty_level: "intermediate",
      min_players: 2, max_players: 4, ideal_num_players: 2
    )
    assert_equal "side-out-race", drill.slug
  end
end
