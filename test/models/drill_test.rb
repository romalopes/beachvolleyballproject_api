require "test_helper"

class DrillTest < ActiveSupport::TestCase
  def valid_attributes(overrides = {})
    {
      title: "Serve Drill",
      setup_instructions: "Serve and recover.",
      training_stage: "beginning",
      difficulty_level: "intermediate",
      min_players: 2,
      max_players: 8,
      ideal_num_players: 4
    }.merge(overrides)
  end

  test "accepts valid training attributes" do
    assert Drill.new(valid_attributes).valid?
  end

  test "defaults apply on new records" do
    drill = Drill.new(title: "Defaults Drill")
    assert_equal "beginning", drill.training_stage
    assert_equal "intermediate", drill.difficulty_level
    assert_equal 2, drill.min_players
    assert_equal 8, drill.max_players
    assert_equal 4, drill.ideal_num_players
    assert drill.valid?
  end

  test "rejects unknown training stage" do
    drill = Drill.new(valid_attributes(training_stage: "preps"))
    assert_not drill.valid?
    assert_includes drill.errors.attribute_names, :training_stage
  end

  test "rejects unknown difficulty" do
    drill = Drill.new(valid_attributes(difficulty_level: "expert"))
    assert_not drill.valid?
    assert_includes drill.errors.attribute_names, :difficulty_level
  end

  test "rejects min greater than max" do
    drill = Drill.new(valid_attributes(min_players: 8, max_players: 2, ideal_num_players: 4))
    assert_not drill.valid?
    assert_includes drill.errors.attribute_names, :min_players
  end

  test "rejects ideal below min" do
    drill = Drill.new(valid_attributes(min_players: 2, max_players: 8, ideal_num_players: 1))
    assert_not drill.valid?
    assert_includes drill.errors.attribute_names, :ideal_num_players
  end

  test "rejects ideal above max" do
    drill = Drill.new(valid_attributes(min_players: 2, max_players: 4, ideal_num_players: 8))
    assert_not drill.valid?
    assert_includes drill.errors.attribute_names, :ideal_num_players
  end

  test "accepts ideal equal to range boundaries" do
    assert Drill.new(valid_attributes(min_players: 2, max_players: 4, ideal_num_players: 2)).valid?
    assert Drill.new(valid_attributes(min_players: 2, max_players: 4, ideal_num_players: 4)).valid?
  end

  test "rejects null training attributes" do
    drill = Drill.new(valid_attributes(
      training_stage: nil,
      difficulty_level: nil,
      min_players: nil,
      max_players: nil,
      ideal_num_players: nil
    ))
    assert_not drill.valid?
  end

  test "range and ideal labels" do
    drill = Drill.new(valid_attributes(min_players: 2, max_players: 4, ideal_num_players: 3))
    assert_equal "2–4 players", drill.player_range_label
    assert_equal "Ideal: 3", drill.ideal_label
    assert_equal "Beginning", drill.training_stage_label
    single = Drill.new(valid_attributes(min_players: 2, max_players: 2, ideal_num_players: 2))
    assert_equal "2 players", single.player_range_label
    assert_equal "Warm-up", Drill.new(valid_attributes(training_stage: "warmup")).training_stage_label
  end
end
