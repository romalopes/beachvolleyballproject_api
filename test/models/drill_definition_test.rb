require "test_helper"

class DrillDefinitionTest < ActiveSupport::TestCase
  def valid_attributes(overrides = {})
    {
      title: "Serve Drill",
      setup_instructions: "Serve and recover.",
      training_stage: "beginning",
      difficulty_level: "intermediate",
      min_players: 2,
      max_players: 8,
      ideal_num_players: 4,
    }.merge(overrides)
  end

  # A minimal but fully valid v1 definition (schema + domain).
  def minimal_definition
    {
      "version" => 1,
      "view" => { "orientation" => "top_down" },
      "court" => { "grid" => { "columns" => 5, "rows" => 4 } },
      "participants" => [
        { "id" => "P1", "type" => "player", "role" => "attacker" },
      ],
      "balls" => [
        { "id" => "B1", "type" => "volleyball" },
      ],
      "objects" => [],
      "steps" => [
        {
          "id" => "S1",
          "description" => "Initial setup.",
          "participants" => [
            { "id" => "P1", "active" => true, "location" => { "court" => "court_1", "x" => 3, "y" => 2 } },
          ],
          "balls" => [
            { "id" => "B1", "active" => true, "location" => { "court" => "court_1", "x" => 3, "y" => 2 } },
          ],
          "objects" => [],
          "actions" => [
            { "participant_id" => "P1", "action" => { "type" => "attack", "description" => "Hit." } },
          ],
          "participant_movements" => [
            { "participant_id" => "P1", "from" => { "court" => "court_1", "x" => 3, "y" => 2 }, "to" => { "court" => "court_1", "x" => 4, "y" => 2 } },
          ],
          "ball_movements" => [
            { "ball_id" => "B1", "from" => { "court" => "court_1", "x" => 3, "y" => 2 }, "to" => { "court" => "court_2", "x" => 3, "y" => 2 } },
          ],
          "object_movements" => [],
        },
        {
          "id" => "S2",
          "description" => "After movement.",
          "participants" => [
            { "id" => "P1", "active" => true, "location" => { "court" => "court_1", "x" => 4, "y" => 2 } },
          ],
          "balls" => [
            { "id" => "B1", "active" => true, "location" => { "court" => "court_2", "x" => 3, "y" => 2 } },
          ],
          "objects" => [],
          "actions" => [],
          "participant_movements" => [],
          "ball_movements" => [],
          "object_movements" => [],
        },
      ],
    }
  end

  # --- Schema validation ---

  test "accepts drill with empty definition (no visualisation yet)" do
    assert Drill.new(valid_attributes).valid?
    assert_equal({}, Drill.new(valid_attributes).definition)
  end

  test "accepts drill with valid definition" do
    drill = Drill.new(valid_attributes(definition: minimal_definition))
    assert drill.valid?, "Expected valid but got errors: #{drill.errors.full_messages.join(', ')}"
  end

  test "rejects invalid orientation" do
    defn = minimal_definition.merge("view" => { "orientation" => "sideways" })
    drill = Drill.new(valid_attributes(definition: defn))
    assert_not drill.valid?
    assert drill.errors[:definition].any? { |e| e.include?("schema") }
  end

  test "rejects invalid action type" do
    defn = JSON.parse(minimal_definition.to_json)
    defn["steps"][0]["actions"] = [{ "participant_id" => "P1", "action" => { "type" => "fly" } }]
    drill = Drill.new(valid_attributes(definition: defn))
    assert_not drill.valid?
    assert drill.errors[:definition].any? { |e| e.include?("schema") }
  end

  test "rejects invalid participant type" do
    defn = JSON.parse(minimal_definition.to_json)
    defn["participants"] = [{ "id" => "P1", "type" => "referee" }]
    drill = Drill.new(valid_attributes(definition: defn))
    assert_not drill.valid?
    assert drill.errors[:definition].any? { |e| e.include?("schema") }
  end

  test "rejects unsupported version" do
    defn = minimal_definition.merge("version" => 2)
    drill = Drill.new(valid_attributes(definition: defn))
    assert_not drill.valid?
    assert drill.errors[:definition].any? { |e| e.include?("schema") }
  end

  test "rejects additional properties at root" do
    defn = minimal_definition.merge("bogus" => true)
    drill = Drill.new(valid_attributes(definition: defn))
    assert_not drill.valid?
    assert drill.errors[:definition].any? { |e| e.include?("schema") }
  end

  # --- Reference validation ---

  test "rejects duplicate participant ids" do
    defn = JSON.parse(minimal_definition.to_json)
    defn["participants"] = [
      { "id" => "P1", "type" => "player" },
      { "id" => "P1", "type" => "player" },
    ]
    drill = Drill.new(valid_attributes(definition: defn))
    assert_not drill.valid?
    assert drill.errors[:definition].any? { |e| e.include?("duplicate") && e.include?("participant") }
  end

  test "rejects action referencing unknown participant" do
    defn = JSON.parse(minimal_definition.to_json)
    defn["steps"][0]["actions"] = [{ "participant_id" => "P99", "action" => { "type" => "attack" } }]
    drill = Drill.new(valid_attributes(definition: defn))
    assert_not drill.valid?
    assert drill.errors[:definition].any? { |e| e.include?("unknown participant") }
  end

  test "rejects movement referencing unknown ball" do
    defn = JSON.parse(minimal_definition.to_json)
    defn["steps"][0]["ball_movements"] = [{ "ball_id" => "B99", "to" => { "court" => "court_1", "x" => 1, "y" => 1 } }]
    drill = Drill.new(valid_attributes(definition: defn))
    assert_not drill.valid?
    assert drill.errors[:definition].any? { |e| e.include?("unknown ball") }
  end

  # --- Entity state validation ---

  test "rejects active participant without location" do
    defn = JSON.parse(minimal_definition.to_json)
    defn["steps"][0]["participants"] = [{ "id" => "P1", "active" => true }]
    drill = Drill.new(valid_attributes(definition: defn))
    assert_not drill.valid?
    assert drill.errors[:definition].any? { |e| e.include?("must have a location") }
  end

  test "rejects inactive participant with location" do
    defn = JSON.parse(minimal_definition.to_json)
    defn["steps"][0]["participants"] = [
      { "id" => "P1", "active" => false, "location" => { "court" => "court_1", "x" => 3, "y" => 2 } },
    ]
    drill = Drill.new(valid_attributes(definition: defn))
    assert_not drill.valid?
    assert drill.errors[:definition].any? { |e| e.include?("must not have a location") }
  end

  # --- Coordinate bounds validation ---

  test "rejects out-of-bounds coordinate" do
    defn = JSON.parse(minimal_definition.to_json)
    defn["steps"][0]["participants"] = [
      { "id" => "P1", "active" => true, "location" => { "court" => "court_1", "x" => 99, "y" => 2 } },
    ]
    drill = Drill.new(valid_attributes(definition: defn))
    assert_not drill.valid?
    assert drill.errors[:definition].any? { |e| e.include?("out of bounds") }
  end

  test "accepts extended-area coordinate when enabled" do
    defn = JSON.parse(minimal_definition.to_json)
    defn["court"] = { "grid" => { "columns" => 5, "rows" => 4 }, "extended_area" => { "enabled" => true, "left" => true, "court_1" => true } }
    defn["steps"][0]["participants"] = [
      { "id" => "P1", "active" => true, "location" => { "court" => "court_1", "x" => 0.5, "y" => 3.25 } },
    ]
    defn["steps"][0]["balls"] = [
      { "id" => "B1", "active" => true, "location" => { "court" => "court_1", "x" => 0.5, "y" => 3.25 } },
    ]
    defn["steps"][0]["participant_movements"] = [
      { "participant_id" => "P1", "from" => { "court" => "court_1", "x" => 0.5, "y" => 3.25 }, "to" => { "court" => "court_1", "x" => 4, "y" => 2 } },
    ]
    defn["steps"][0]["ball_movements"] = [
      { "ball_id" => "B1", "from" => { "court" => "court_1", "x" => 0.5, "y" => 3.25 }, "to" => { "court" => "court_2", "x" => 3, "y" => 2 } },
    ]
    defn["steps"][1]["participants"] = [
      { "id" => "P1", "active" => true, "location" => { "court" => "court_1", "x" => 4, "y" => 2 } },
    ]
    drill = Drill.new(valid_attributes(definition: defn))
    assert drill.valid?, "Expected valid but got: #{drill.errors[:definition].join(', ')}"
  end

  # --- Movement consistency validation ---

  test "rejects movement origin that does not match current state" do
    defn = JSON.parse(minimal_definition.to_json)
    defn["steps"][0]["participant_movements"] = [
      { "participant_id" => "P1", "from" => { "court" => "court_1", "x" => 1, "y" => 1 }, "to" => { "court" => "court_1", "x" => 4, "y" => 2 } },
    ]
    drill = Drill.new(valid_attributes(definition: defn))
    assert_not drill.valid?
    assert drill.errors[:definition].any? { |e| e.include?("origin does not match") }
  end

  test "rejects movement target that does not match next step" do
    defn = JSON.parse(minimal_definition.to_json)
    defn["steps"][0]["participant_movements"] = [
      { "participant_id" => "P1", "from" => { "court" => "court_1", "x" => 3, "y" => 2 }, "to" => { "court" => "court_1", "x" => 9, "y" => 9 } },
    ]
    drill = Drill.new(valid_attributes(definition: defn))
    assert_not drill.valid?
    assert drill.errors[:definition].any? { |e| e.include?("target does not match") }
  end
end

