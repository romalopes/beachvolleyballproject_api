# Phase 5: let an Assessment reference a definition, and relax exactly the three
# constraints that assume every rating has a single typed entry.
#
# The derived aggregate has no typed counterpart — `score` is computed from the
# children, so `reported_value`/`scale` belong to each child instead (plan D9/D10).
# Nothing else changes: legacy rows keep their rubric, their score pair and
# their payload shape, and no existing row is rewritten.
class AddDefinitionSupportToAssessments < ActiveRecord::Migration[8.1]
  def up
    add_reference :assessments, :assessment_definition, foreign_key: true

    # 1. score/reported_value are a pair only for legacy single-rubric rows.
    remove_check_constraint :assessments, name: "assessments_score_pair"
    add_check_constraint :assessments,
                         "assessment_definition_id IS NOT NULL OR " \
                         "((score IS NULL) = (reported_value IS NULL))",
                         name: "assessments_score_pair"

    # 2. Publishing still requires a score; a typed value is only required when
    #    the row is a legacy rating (a weighted result derives its score).
    remove_check_constraint :assessments, name: "assessments_published_requires_score"
    add_check_constraint :assessments,
                         "status = 'draft' OR (score IS NOT NULL AND " \
                         "(assessment_definition_id IS NOT NULL OR reported_value IS NOT NULL))",
                         name: "assessments_published_requires_score"

    # 3. Exactly one rubric *kind* per row: a definition or a legacy rubric,
    #    never both and (for definition rows) never neither.
    add_check_constraint :assessments,
                         "assessment_definition_id IS NULL OR " \
                         "(category_id IS NULL AND custom_category IS NULL)",
                         name: "assessment_definition_xor_rubric"

    # 4. Phase 4's rubric XOR demanded exactly one of category_id/custom_category
    #    on *every* row, which a definition-based row (neither) cannot satisfy.
    #    The constraint keeps its name — it is still the rubric XOR, it just lets
    #    a definition stand in for the rubric. Note the branch above already
    #    guarantees both columns are NULL when a definition is present, so this
    #    pair of constraints states the whole rule:
    #      definition NULL  -> exactly one rubric column
    #      definition set   -> neither rubric column
    remove_check_constraint :assessments, name: "assessments_category_xor_custom_category"
    add_check_constraint :assessments,
                         "assessment_definition_id IS NOT NULL OR " \
                         "((category_id IS NOT NULL AND custom_category IS NULL) OR " \
                         "(category_id IS NULL AND custom_category IS NOT NULL))",
                         name: "assessments_category_xor_custom_category"

    # The parent's scale is meaningless for a weighted result — each child
    # carries its own — so the column must be able to hold NULL for those rows.
    change_column_null :assessments, :scale, true
  end

  def down
    # Rolling back is only possible while no definition-based rows exist: their
    # NULL `scale`/`reported_value` cannot satisfy the original constraints, and
    # the whole point of the migration is that no rating is destroyed to make a
    # schema change fit.
    leftover = select_value(
      "SELECT COUNT(*) FROM assessments WHERE assessment_definition_id IS NOT NULL"
    ).to_i
    if leftover.positive?
      raise ActiveRecord::IrreversibleMigration,
            "#{leftover} definition-based assessment(s) must be removed before this can roll back"
    end

    remove_check_constraint :assessments, name: "assessment_definition_xor_rubric"

    # Back to the strict Phase 4 rubric XOR: exactly one of the two columns.
    remove_check_constraint :assessments, name: "assessments_category_xor_custom_category"
    add_check_constraint :assessments,
                         "(category_id IS NOT NULL AND custom_category IS NULL) OR " \
                         "(category_id IS NULL AND custom_category IS NOT NULL)",
                         name: "assessments_category_xor_custom_category"

    remove_check_constraint :assessments, name: "assessments_published_requires_score"
    add_check_constraint :assessments,
                         "status = 'draft' OR (score IS NOT NULL AND reported_value IS NOT NULL)",
                         name: "assessments_published_requires_score"

    remove_check_constraint :assessments, name: "assessments_score_pair"
    add_check_constraint :assessments,
                         "(score IS NULL) = (reported_value IS NULL)",
                         name: "assessments_score_pair"

    remove_reference :assessments, :assessment_definition, foreign_key: true
    change_column_null :assessments, :scale, false
  end
end
