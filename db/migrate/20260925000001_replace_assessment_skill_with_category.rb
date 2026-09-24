# Phase 4 follow-up: an assessment rubric is a Category, not a single Skill.
#
# A coach rates a player against the *area* they observed ("Attack", "Serve"),
# which is what the catalogue already models as a Category; the Skill level is
# the drill/training-focus vocabulary. Keeping the old skill columns would have
# left two competing rubrics on the table and an XOR that only permitted one of
# them.
#
# Existing rows are migrated, not dropped:
#   * a skill-linked row adopts that skill's category — the assessment keeps its
#     meaning at the level the club now reasons about;
#   * a free-text row's text becomes `custom_category`, so a rubric somebody
#     typed is never lost.
#
# The forward direction is lossy in one way and the `down` path says so: once a
# skill has been collapsed to its category, the exact skill is not recoverable,
# so the rollback restores the category *name* as free text rather than
# pretending to know which skill was originally recorded.
class ReplaceAssessmentSkillWithCategory < ActiveRecord::Migration[8.1]
  def up
    add_reference :assessments, :category, foreign_key: true
    add_column :assessments, :custom_category, :string

    # Backfill before the old columns go away: the category of the recorded
    # skill, and the free text as itself. A row with neither is impossible —
    # the old check constraint required exactly one.
    execute <<~SQL.squish
      UPDATE assessments
      SET category_id = skills.category_id
      FROM skills
      WHERE assessments.skill_id = skills.id
    SQL

    execute "UPDATE assessments SET custom_category = custom_skill WHERE custom_skill IS NOT NULL"

    remove_check_constraint :assessments, name: "assessments_skill_xor_custom_skill"
    remove_reference :assessments, :skill, foreign_key: true
    remove_column :assessments, :custom_skill

    # The rubric rule is unchanged in spirit — exactly one branch — but the
    # branches are now a category or free text.
    add_check_constraint :assessments,
                         "(category_id IS NOT NULL AND custom_category IS NULL) OR " \
                         "(category_id IS NULL AND custom_category IS NOT NULL)",
                         name: "assessments_category_xor_custom_category"
  end

  def down
    add_column :assessments, :skill_id, :bigint
    add_column :assessments, :custom_skill, :string

    # See the class comment: the skill is not recoverable, so every row comes
    # back as its rubric label in the free-text branch.
    execute <<~SQL.squish
      UPDATE assessments
      SET custom_skill = COALESCE(
        custom_category,
        (SELECT name FROM categories WHERE categories.id = assessments.category_id)
      )
    SQL

    remove_check_constraint :assessments, name: "assessments_category_xor_custom_category"
    remove_reference :assessments, :category, foreign_key: true
    remove_column :assessments, :custom_category

    add_index :assessments, :skill_id
    add_foreign_key :assessments, :skills

    add_check_constraint :assessments,
                         "(skill_id IS NOT NULL AND custom_skill IS NULL) OR " \
                         "(skill_id IS NULL AND custom_skill IS NOT NULL)",
                         name: "assessments_skill_xor_custom_skill"
  end
end
