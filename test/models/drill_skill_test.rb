require "test_helper"

class DrillSkillTest < ActiveSupport::TestCase
  test "links a drill to a skill" do
    link = DrillSkill.new(drill: drills(:one), skill: skills(:one))
    assert link.valid?
    assert_difference("DrillSkill.count") do
      link.save!
    end
  end

  test "requires a drill" do
    link = DrillSkill.new(skill: skills(:one))
    assert_not link.valid?
    assert_includes link.errors.attribute_names, :drill
  end

  test "requires a skill" do
    link = DrillSkill.new(drill: drills(:one))
    assert_not link.valid?
    assert_includes link.errors.attribute_names, :skill
  end

  test "exposes the drill's skills through the join" do
    skill = skills(:two)
    DrillSkill.create!(drill: drills(:one), skill: skill)
    assert_includes drills(:one).reload.skills.map(&:id), skill.id
  end

  test "destroying a drill removes its drill/skill links" do
    drill = drills(:one)
    DrillSkill.create!(drill: drill, skill: skills(:one))
    assert_difference("DrillSkill.count", -1) do
      drill.destroy
    end
  end
end
