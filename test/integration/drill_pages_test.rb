require "test_helper"

# The public drill pages are server-rendered (Hotwire), so they must tolerate a
# drill whose optional training attributes were never filled in: no stray empty
# stat spans, no "Min:  · Max:" artifacts, just the title and what exists.
class DrillPagesTest < ActionDispatch::IntegrationTest
  setup do
    @drill = Drill.create!(
      title: "Metadata Free Drill",
      setup_instructions: "Pair up and rally.",
      definition: {}
    )
  end

  test "index lists a drill that has no training attributes" do
    get "/drills"
    assert_response :success
    assert_includes response.body, "Metadata Free Drill"
  end

  test "show renders a drill that has no training attributes" do
    get "/drills/#{@drill.slug}"
    assert_response :success
    assert_includes response.body, "Metadata Free Drill"
    # The player-range pill is only rendered with data; an empty one would show
    # as a bare "Min:" / "Max:" label.
    assert_not_includes response.body, "Min: &middot; Max:"
  end

  test "show renders only the player range sides that were provided" do
    @drill.update!(min_players: 2)
    get "/drills/#{@drill.slug}"
    assert_response :success
    assert_includes response.body, "Min: 2"
    assert_not_includes response.body, "Max:"
  end

  test "skill page renders a metadata-free related drill without empty separators" do
    skill = skills(:one)
    DrillSkill.create!(drill: @drill, skill: skill)
    get "/skills/#{skill.slug}"
    assert_response :success
    assert_includes response.body, "Metadata Free Drill"
    assert_not_includes response.body, "&middot;  &middot;"
  end
end
