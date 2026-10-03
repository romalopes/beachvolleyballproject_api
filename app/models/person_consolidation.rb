class PersonConsolidation < ApplicationRecord
  belongs_to :source_person, class_name: "Person"
  belongs_to :canonical_person, class_name: "Person"
  belongs_to :performed_by, class_name: "User"

  validates :source_person_id, uniqueness: true
  validate :people_are_distinct

  private

  def people_are_distinct
    errors.add(:canonical_person, "must be different from the source person") if source_person_id.present? && source_person_id == canonical_person_id
  end
end
