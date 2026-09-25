class MigrateLegacyAssessmentsToWeightedDefinitions < ActiveRecord::Migration[8.1]
  class LegacyAssessment < ActiveRecord::Base
    self.table_name = "assessments"
  end

  class Definition < ActiveRecord::Base
    self.table_name = "assessment_definitions"
  end

  class Category < ActiveRecord::Base
    self.table_name = "assessment_categories"
  end

  class Score < ActiveRecord::Base
    self.table_name = "assessment_category_scores"
  end

  class CustomCategory < ActiveRecord::Base
    self.table_name = "category_customs"
  end

  def up
    now = Time.current

    LegacyAssessment.where(assessment_definition_id: nil).find_each do |assessment|
      label = legacy_label(assessment)
      next if label.blank?

      definition_id = insert_definition(assessment, label, now)

      category_id = insert_category(
        definition_id: definition_id,
        assessment: assessment,
        label: label,
        now: now
      )

      if assessment.reported_value.present? || assessment.score.present?
        insert_score(assessment: assessment, category_id: category_id, now: now)
      end

      # The definition is the canonical rubric from this point forward. The
      # original numeric result remains on the parent and in the child row, so
      # no historical score is recalculated or discarded.
      assessment.update_columns(
        assessment_definition_id: definition_id,
        category_id: nil,
        custom_category: nil,
        updated_at: assessment.updated_at || now
      )
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "Migrated assessments must be restored from a database backup before rolling back"
  end

  private

  def legacy_label(assessment)
    if assessment.category_id.present?
      category = Category.connection.select_value(
        "SELECT name FROM categories WHERE id = #{Integer(assessment.category_id)}"
      )
      category.presence || "Category #{assessment.category_id}"
    else
      assessment.custom_category.to_s.strip
    end
  end

  def insert_definition(assessment, label, now)
    result = Definition.insert!({
      name: "Migrated: #{label}",
      status: assessment.status == "active" ? "active" : "draft",
      created_by_id: assessment.created_by_id,
      created_at: now,
      updated_at: now
    })
    result.id
  end

  def insert_category(definition_id:, assessment:, label:, now:)
    result = Category.insert!({
      assessment_definition_id: definition_id,
      category_id: assessment.category_id,
      category_custom_id: assessment.category_id.nil? ? custom_category_id(assessment, label, now) : nil,
      weight: 100,
      position: 0,
      created_at: now,
      updated_at: now
    })
    result.id
  end

  def insert_score(assessment:, category_id:, now:)
    Score.insert!({
      assessment_id: assessment.id,
      assessment_category_id: category_id,
      score: assessment.score,
      reported_value: assessment.reported_value,
      scale: assessment.scale.presence || "one_to_ten",
      created_at: now,
      updated_at: now
    })
  end

  def custom_category_id(assessment, label, now)
    existing = CustomCategory.where(created_by_id: assessment.created_by_id)
                             .where("LOWER(name) = LOWER(?)", label)
                             .order(:id).first
    return existing.id if existing

    CustomCategory.create!(
      name: label,
      visibility: "private",
      created_by_id: assessment.created_by_id,
      created_at: now,
      updated_at: now
    ).id
  end
end
