# A minimal but fully valid v1 drill definition (schema + domain), shared by
# tests that need a drill carrying a renderable visualisation.
module DrillDefinitionTestHelper
  def visual_drill_definition
    {
      "version" => 1,
      "side" => { "grid" => { "columns" => 5, "rows" => 4 } },
      "participants" => [
        { "id" => "P1", "type" => "player" },
      ],
      "balls" => [
        { "id" => "B1", "type" => "volleyball" },
      ],
      "objects" => [],
      "steps" => [
        {
          "id" => "S1",
          "participants" => [
            { "id" => "P1", "active" => true, "location" => { "side" => "side_1", "x" => 3, "y" => 2 } },
          ],
          "balls" => [
            { "id" => "B1", "active" => true, "location" => { "side" => "side_1", "x" => 3, "y" => 2 } },
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
end
