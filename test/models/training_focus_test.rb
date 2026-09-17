require "test_helper"

class TrainingFocusTest < ActiveSupport::TestCase
  test "accepts a skill-based focus" do
    focus = training_focuses(:serve_reception)
    assert focus.valid?
    assert focus.skill_based?
    assert_not focus.custom?
    assert_equal skills(:one).title, focus.label
  end

  test "accepts a custom-text focus" do
    focus = training_focuses(:transition_communication)
    assert focus.valid?
    assert focus.custom?
    assert_not focus.skill_based?
    assert_nil focus.skill_id
    assert_equal "Transition communication", focus.label
  end

  test "rejects a focus with neither a skill nor custom text" do
    focus = TrainingFocus.new(training_session: training_sessions(:one), position: 2)
    assert_not focus.valid?
    assert_includes focus.errors.full_messages,
                    "A training focus must reference a skill or provide custom focus text"
  end

  test "rejects a focus with both a skill and custom text" do
    focus = TrainingFocus.new(training_session: training_sessions(:one),
                              skill: skills(:two), custom_focus: "Both")
    assert_not focus.valid?
    assert_includes focus.errors.full_messages,
                    "A training focus cannot reference a skill and custom text at the same time"
  end

  test "rejects the same skill twice within one training" do
    focus = TrainingFocus.new(training_session: training_sessions(:one), skill: skills(:one))
    assert_not focus.valid?
    assert_includes focus.errors.attribute_names, :skill_id
  end

  test "allows the same skill in a different training" do
    focus = TrainingFocus.new(training_session: training_sessions(:three), skill: skills(:one))
    assert focus.valid?
  end

  test "allows repeated custom focus text" do
    first = training_focuses(:transition_communication)
    duplicate = TrainingFocus.new(training_session: first.training_session,
                                  custom_focus: first.custom_focus)
    assert duplicate.valid?
  end

  test "rejects a skill id that does not exist" do
    focus = TrainingFocus.new(training_session: training_sessions(:one), skill_id: 999_999)
    assert_not focus.valid?
    assert_includes focus.errors.full_messages, "Skill must exist"
  end

  test "stores the description independently from the skill" do
    focus = training_focuses(:serve_reception)
    assert_equal "Focus on platform angle against float serves.", focus.description
    assert_not_equal focus.description, focus.skill.description

    focus.update!(description: "Focus on reading the server.")
    assert_equal "Focus on reading the server.", focus.reload.description
    assert_not_equal "Focus on reading the server.", focus.skill.reload.description
  end

  test "normalizes blank custom text to nil" do
    focus = TrainingFocus.new(training_session: training_sessions(:one),
                              skill: skills(:two), custom_focus: "   ")
    assert focus.valid?, focus.errors.full_messages.inspect
    assert_nil focus.custom_focus
  end

  test "keeps the intentional position order" do
    assert_equal [0, 1], training_sessions(:one).training_focuses.map(&:position)
    assert_equal [training_focuses(:serve_reception).id,
                  training_focuses(:transition_communication).id],
                 training_sessions(:one).training_focuses.map(&:id)
  end
end