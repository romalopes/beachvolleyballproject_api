# A reusable weighted assessment configuration — "A-Level Assessment" = Attack
# 40 · Defense 30 · Serve 20 · Strategy 10.
#
# It is deliberately *not* an Assessment: an Assessment is one coach's rating of
# one player (Phase 4) and must keep that shape, while a definition is authored
# once and applied to many players. The two are joined by
# `assessments.assessment_definition_id`.
#
# Two lifecycle rules carry most of the weight:
#   * `active` requires the weights to total exactly 100 — a draft may be
#     unbalanced while it is being built, which is why the total is validated on
#     status rather than on every save;
#   * a definition that results point at is frozen (plan D7): edit it by
#     duplicating it, never in place, so a historical score keeps meaning what
#     it meant.
#
# Retirement is two-tier, because "unused" and "no longer wanted" are different
# requests. `archived` is the soft delete: reversible, and the ordinary way to
# retire a configuration, since a coach must be able to bring it back. A hard
# delete is admin-only and only for a definition nothing points at — see
# `usage_counts`, which exists because four tables reference this one and a
# delete that only checked the obvious one would fail as a raw FK error.
class AssessmentDefinition < ApplicationRecord
  STATUSES = %w[draft active archived].freeze
  TARGET_WEIGHT = 100

  belongs_to :created_by, class_name: "User", optional: true
  has_many :assessment_categories, -> { order(:position, :id) },
           dependent: :destroy, inverse_of: :assessment_definition
  has_many :assessments, dependent: :restrict_with_error
  # Declared explicitly so deleting is refused in a way a controller can explain,
  # rather than by a foreign-key violation escaping as a 500.
  has_many :assessment_sessions, dependent: :restrict_with_error, inverse_of: :assessment_definition
  has_many :ranking_consolidations, dependent: :restrict_with_error, inverse_of: :assessment_definition

  accepts_nested_attributes_for :assessment_categories, allow_destroy: true, reject_if: :all_blank

  normalizes :name, with: ->(value) { value.strip.presence }

  validates :name, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }

  validate :active_requires_total_weight_of_100
  validate :configuration_is_frozen_once_referenced, on: :update

  scope :ordered, -> { order(:name, :id) }
  scope :with_status, ->(status) { status.present? ? where(status: status) : all }

  def total_weight
    assessment_categories.reject(&:marked_for_destruction?).sum { |row| row.weight.to_i }
  end

  def remaining_weight
    TARGET_WEIGHT - total_weight
  end

  def weights_balanced?
    total_weight == TARGET_WEIGHT
  end

  def draft?
    status == "draft"
  end

  def active?
    status == "active"
  end

  def archived?
    status == "archived"
  end

  def status_label
    status.to_s.capitalize
  end

  # Does at least one assessment already quote this configuration? If so the
  # configuration is history.
  def referenced?
    assessments.exists?
  end

  # What points at this definition, by table. Deliberately wider than `referenced?`:
  # that one asks "is this configuration frozen" (D7, which is about scores already
  # recorded), while this one asks "may this row be deleted at all". A session may
  # quote a definition with no results yet and still make a hard delete wrong.
  #
  # `assessment_categories` is omitted: those are owned by the definition and are
  # destroyed with it, which is the point of deleting one.
  def usage_counts
    {
      assessments: assessments.count,
      assessment_sessions: assessment_sessions.count,
      ranking_consolidations: ranking_consolidations.count
    }
  end

  def in_use?
    usage_counts.values.any?(&:positive?)
  end

  # Human labels for the blockers, so the refusal names what is in the way instead
  # of saying "Invalid".
  USAGE_LABELS = {
    assessments: "recorded assessment(s)",
    assessment_sessions: "assessment session(s)",
    ranking_consolidations: "ranking consolidation(s)"
  }.freeze

  def usage_summary
    usage_counts.filter_map do |key, count|
      next if count.zero?

      "#{count} #{USAGE_LABELS.fetch(key)}"
    end.join(", ")
  end

  # Archiving is the reversible retirement, so it is available from either live
  # state and never blocked by usage — hiding a configuration that is still in use
  # is exactly the wrong response to wanting it out of the picker.
  def archivable?
    !archived?
  end

  def restorable?
    archived?
  end

  # A hard delete is only honest when nothing references the row, and only an
  # admin may do it (the controller enforces that half).
  def deletable?
    !in_use?
  end

  def metadata
    {
      id: id,
      name: name,
      description: description,
      status: status,
      status_label: status_label,
      total_weight: total_weight,
      remaining_weight: remaining_weight,
      weights_balanced: weights_balanced?,
      referenced: referenced?,
      # What blocks a hard delete, so the UI can say why an admin cannot remove
      # this rather than offering a button that fails.
      usage_counts: usage_counts,
      in_use: in_use?,
      deletable: deletable?,
      usage_summary: usage_summary,
      archivable: archivable?,
      restorable: restorable?,
      created_by: created_by ? { id: created_by.id, name: created_by.name } : nil,
      assessment_categories: assessment_categories.map(&:metadata),
      created_at: created_at,
      updated_at: updated_at
    }
  end

  private

  # A definition may be saved unbalanced while it is a draft; only activating it
  # demands the full 100. The message names the number, never "Invalid".
  def active_requires_total_weight_of_100
    return unless status == "active"
    return if weights_balanced?

    errors.add(
      :base,
      "The assessment weights must total 100%. Current total: #{total_weight}%."
    )
  end

  # D7: an in-use configuration is frozen. Status changes are still allowed
  # (archiving is the supported way to retire it) — it is the *identity* (name)
  # and the *category set* that may no longer move.
  def configuration_is_frozen_once_referenced
    return unless referenced?
    return unless will_save_change_to_name? || categories_reconfigured?

    errors.add(:base, "This assessment definition is in use; duplicate it to make changes.")
  end

  # Nested attributes have already been assigned by the time validation runs, so
  # the association's target — not the database — is what tells us the set moved.
  def categories_reconfigured?
    association(:assessment_categories).target.any? do |row|
      row.new_record? || row.marked_for_destruction? || row.changed_for_autosave?
    end
  end
end
