# A coach's assessment of a player, against a category (or a free-text rubric).
#
# The rubric is deliberately the *category* — the area of the game the coach
# observed ("Attack", "Serve") — not a single Skill. A Skill is the vocabulary a
# training focus or drill names; an assessment describes a player's level in an
# area, which is the coarser and more stable unit.
#
# Both sides are *profiles*, never people or accounts: an assessment is always
# about a PlayerProfile and always attributed to a CoachProfile — the same
# reasoning as the visibility work in Phase 3, where ownership lives on the
# profile so one Person can hold both roles without them being confused.
#
# `score` is the canonical 0..100 rating; `reported_value` + `scale` keep what
# the coach actually typed, so a later change to the band table is a data
# migration instead of a guess (see RatingScale).
#
# Nothing is ever hard-deleted: a row leaves the club's view by becoming
# `withdrawn`, and the profiles refuse to be destroyed while assessments exist.
class Assessment < ApplicationRecord
  STATUSES = %w[draft active withdrawn].freeze

  # Only published assessments are club knowledge. `draft` and `withdrawn` stay
  # with their stakeholders (recorder, attributed coach) and oversight. This is a
  # deliberate divergence from TrainingSession, which keeps `cancelled` public —
  # a retracted *number* about a player is more sensitive than a cancelled
  # schedule entry.
  PUBLICLY_VISIBLE_STATUSES = %w[active].freeze

  SCALES = RatingScale::SCALES

  belongs_to :player_profile
  belongs_to :coach_profile
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :category, optional: true
  belongs_to :assessment_definition, optional: true
  belongs_to :training_session, optional: true

  # Definition-based rows score each configured category; legacy rows have no
  # children (plan D12: their rubric and score stay exactly where they are).
  # Restrict, never destroy — a historical score keeps its inputs.
  has_many :assessment_category_scores, dependent: :restrict_with_error,
                                        inverse_of: :assessment
  accepts_nested_attributes_for :assessment_category_scores

  # `value` is the coach's own entry on the named scale — the only rating input
  # the API accepts besides a canonical `score`. It is virtual: assigning it
  # sets `reported_value` + `scale` and derives `score` through RatingScale, so
  # the conversion runs identically whether the row is built by a controller or
  # in the console.
  attr_writer :value

  def value
    reported_value
  end

  def value=(entry)
    return if entry.blank?

    @value = entry
    self.scale = scale.presence || RatingScale::DEFAULT_SCALE
    number = Integer(entry, exception: false)
    return unless RatingScale.legal_value?(number, scale: scale)

    self.reported_value = number
    self.score = RatingScale.to_score(number, scale: scale)
  end

  # Blank custom text must become NULL, otherwise a category-based row would
  # carry an empty string and violate the category-xor-custom check constraint.
  normalizes :custom_category, with: ->(value) { value.strip.presence }

  # A weighted result has no typed counterpart: `score` is derived from the
  # children, so the legacy `reported_value`/`scale` pair belongs to each child
  # (plan D10). Clearing them here keeps the parent's columns honest instead of
  # leaving a default `one_to_ten` on a row that was never typed on any scale.
  before_validation :clear_legacy_rating_fields, if: :definition_based?

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :scale, presence: true, inclusion: { in: SCALES }, unless: :definition_based?
  validates :score, allow_nil: true, numericality: {
    only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100
  }
  validates :reported_value, allow_nil: true, numericality: { only_integer: true }

  validate :reported_value_exists_on_its_scale
  validate :score_and_reported_value_travel_together
  validate :score_matches_reported_value
  validate :rated_once_it_leaves_draft
  validate :definition_or_legacy_rubric
  validate :definition_must_be_active_to_attach
  validate :definition_fully_scored_when_active
  validate :coach_must_not_assess_their_own_player_profile

  scope :active, -> { where(status: "active") }
  scope :ordered, -> { order(created_at: :desc, id: :desc) }

  # Existence: who may see a row at all.
  #
  # A row exists for you when it is `active` and the assessed player exists for
  # you (the soft visibility rule of Phase 3.C), or when you are a stakeholder —
  # recorder or attributed coach — in any status, or when you are oversight
  # (curator/admin). With nobody signed in, only published rows on visible
  # players exist: the same public view TrainingSession.visible_to gives a guest.
  #
  # There is deliberately no `include_private` equivalent here: visibility is
  # not a switch a client can flip, so nothing widens what exists beyond this
  # scope. The player ids are plucked first — the same idiom
  # TrainingSession.visible_to uses, and the only way to keep `.or`
  # structurally compatible across the branches.
  scope :visible_to, ->(user) {
    return all if Assessment.oversight?(user)

    published = where(status: PUBLICLY_VISIBLE_STATUSES)
                  .where(player_profile_id: PlayerProfile.visible_to(user).pluck(:id))
    # Without this guard the `created_by_id: nil` branch below would match
    # unrecorded rows in every status, drafts included.
    return published if user.nil?

    own = where(created_by_id: user.id)
    attributed = where(coach_profile_id: user.person&.coach_profile&.id)
    own.or(attributed).or(published)
  }

  # Oversight is the curator/admin pair — deliberately NOT User#content_manager?.
  #
  # For the shared schedule a coach counts as a manager (User#content_manager?),
  # because a session created yesterday by one coach must stay manageable by the
  # others. An assessment is different in kind: it is one named coach's
  # professional claim about a player, so only its stakeholders may touch it and
  # only curators and admins oversee all of them. This is the same pair
  # PlayerProfile#visible_to_user? treats as unlimited (phase 3.C).
  def self.oversight?(user)
    user.respond_to?(:admin?) && (user.admin? || user.curator?)
  end

  # Newest row per rubric, for the "current level" view of a player.
  #
  # It takes the relation explicitly because a scope cannot return an array, and
  # a class method called on a relation would silently ignore that relation. A
  # player's history is small by construction, so the grouping happens in Ruby
  # rather than relying on Postgres' DISTINCT ON; `category_key` keeps two
  # distinct free-text rubrics from collapsing into one.
  def self.latest_per_rubric(scope = all)
    scope.ordered.group_by(&:rubric_key).values.map(&:first)
  end

  # The single source of truth for "may this user see this row?", used by the
  # controllers so the rules are never re-implemented at a call site.
  def visible_to_user?(user)
    return true if self.class.oversight?(user)
    return true if stakeholder?(user)
    return false unless publicly_visible?

    player_profile.visible_to_user?(user)
  end

  # Your own work is always yours to see, in any status: this is what keeps a
  # draft — and an active row about a player who is private to somebody else —
  # reachable for the coach who recorded it.
  def stakeholder?(user)
    return false if user.nil?

    created_by_id == user.id || coach_account_user_id == user.id
  end

  # The twin of visible_to_user? for actions: it keys on the same relationships,
  # so "can see" and "can change" can never drift apart.
  def manageable_by?(user)
    self.class.oversight?(user) || stakeholder?(user)
  end

  # The User behind the attributed coach profile, when that coach has an account.
  # A coach recorded without an account is still a valid assessor — their rows
  # are then managed by the recorder and by curators/admins.
  def coach_account_user_id
    coach_profile&.person&.account&.user_id
  end

  def publicly_visible?
    PUBLICLY_VISIBLE_STATUSES.include?(status)
  end

  def draft?
    status == "draft"
  end

  def active?
    status == "active"
  end

  def withdrawn?
    status == "withdrawn"
  end

  def status_label
    status.to_s.capitalize
  end

  # The rubric, whichever branch it sits on. A definition-based row is labelled
  # by its definition; a legacy row by its category or its free text.
  def category_label
    return assessment_definition.name if definition_based?

    category&.name.presence || custom_category
  end

  def category_key
    return "definition:#{assessment_definition_id}" if definition_based?

    category_id ? "category:#{category_id}" : "custom:#{custom_category.to_s.downcase}"
  end

  # Does this row apply a weighted definition rather than carry a single rubric?
  def definition_based?
    assessment_definition_id.present?
  end

  # Every configured category carries a score, and there is at least one.
  # Read from the association target rather than the database so a nested
  # submission is judged on what was submitted, not on what is stored yet.
  def definition_fully_scored?
    return false unless definition_based?
    return false if assessment_definition.nil?

    expected = assessment_definition.assessment_categories.count
    return false if expected.zero?

    rows = assessment_category_scores.to_a
    rows.size == expected && rows.all?(&:rated?)
  end

  # Every configured category, in the order the definition declares. Exposed as
  # a serialized payload so the API can carry a result's breakdown without the
  # SPA needing a second round-trip per assessment.
  def category_scores
    ordered_category_scores.map(&:metadata)
  end

  # Recompute the canonical aggregate from the children. An incomplete set
  # computes to *nil*, never to a partial total: a half-scored assessment must
  # not read as a finished one. `update_column` keeps this out of the callback
  # loop — the children's after_save calls it, and it must not re-save them.
  def recalculate_weighted_score!
    return unless definition_based?
    return unless persisted?

    rows = assessment_category_scores.reload
    update_column(:score, definition_fully_scored? ? weighted_total(rows) : nil)
    score
  end

  # PlayerProfile#latest_rated_assessments groups by this name ("per rubric",
  # in the plan's vocabulary); an alias keeps both readers of the same idea
  # from drifting apart.
  alias_method :rubric_key, :category_key

  # Display values: both scales the club reads, plus the canonical pair. They are
  # nil for an unrated draft, so a caller cannot render a rating of zero.
  def ten_scale
    RatingScale.to_ten(score)
  end

  def five_scale
    RatingScale.to_five(score)
  end

  def score_label
    RatingScale.describe(score)
  end

  def metadata
    {
      id: id,
      player_profile_id: player_profile_id,
      coach_profile_id: coach_profile_id,
      created_by: created_by ? { id: created_by.id, name: created_by.name } : nil,
      category: category ? { id: category.id, name: category.name, slug: category.slug } : nil,
      custom_category: custom_category,
      category_label: category_label,
      assessment_definition: assessment_definition ? {
        id: assessment_definition.id,
        name: assessment_definition.name,
        status: assessment_definition.status,
        total_weight: assessment_definition.total_weight
      } : nil,
      category_scores: category_scores,
      training_session_id: training_session_id,
      score: score,
      reported_value: reported_value,
      scale: scale,
      ten_scale: ten_scale,
      five_scale: five_scale,
      score_label: score_label,
      notes: notes,
      status: status,
      status_label: status_label,
      created_at: created_at,
      updated_at: updated_at
    }
  end

  private

  # The order the coach configured, not insertion order: position is the
  # presentation order the definition carries into every list and report.
  def ordered_category_scores
    assessment_category_scores.sort_by { |row| [ row.assessment_category&.position || 0, row.id || 0 ] }
  end

  # Σ(category_score × weight) / 100, rounded to the canonical integer. The
  # children are already on the 0..100 scale, so this is a plain weighted mean.
  def weighted_total(rows)
    sum = rows.sum { |row| row.score * row.assessment_category.weight }
    (sum / 100.0).round
  end

  # A rating is only meaningful on the scale it was entered on. A weighted
  # result has no typed entry of its own — each child carries one.
  def reported_value_exists_on_its_scale
    return if definition_based?
    return if reported_value.nil?
    return if RatingScale.legal_value?(reported_value, scale: scale)

    errors.add(:reported_value, "is not a value on the #{scale.presence || 'chosen'} scale")
  end

  # The canonical score and the typed value are a pair — the same rule the
  # database enforces — so neither may appear without the other. Mirroring it
  # here turns a constraint violation into a message the coach can act on.
  # A weighted result deliberately breaks the pair (its score is derived), which
  # is exactly what the relaxed constraint allows.
  def score_and_reported_value_travel_together
    return if definition_based?

    if score.present? && reported_value.blank?
      errors.add(:reported_value, "is required when a score is given")
    elsif reported_value.present? && score.blank?
      errors.add(:score, "is required when a reported value is given")
    end
  end

  # `score` is derived from the typed pair, so the two must agree: a row whose
  # canonical score does not follow from `reported_value` would quietly disagree
  # with the band table every other row is measured by.
  def score_matches_reported_value
    return if definition_based?
    return if score.nil? || reported_value.nil? || scale.blank?
    # An illegal value is reported by reported_value_exists_on_its_scale; asking
    # RatingScale for its score here would raise instead of adding an error.
    return unless RatingScale.legal_value?(reported_value, scale: scale)
    return if score == RatingScale.to_score(reported_value, scale: scale)

    errors.add(:score, "does not match the reported value and scale")
  end

  # An unrated row may only be a draft: endorsing, retracting or reinstating all
  # imply a rating exists, otherwise the club would hold an evaluation with no
  # number in it.
  def rated_once_it_leaves_draft
    return if draft? || score.present?

    errors.add(:score, "is required once the assessment leaves draft")
  end

  # Exactly one rubric *kind*: a weighted definition (whose categories live on
  # the definition's own rows) or the Phase 4 pair of category/free text — never
  # both, and never neither.
  def definition_or_legacy_rubric
    if definition_based?
      if category_id.present? || custom_category.present?
        errors.add(:category, "must be blank when an assessment definition is used")
      end
      return
    end

    if category_id.present? && custom_category.present?
      errors.add(:custom_category, "must be blank when a category is selected")
    elsif category_id.blank? && custom_category.blank?
      errors.add(:base, "Choose a category or describe what was assessed")
    end
  end

  # Only an *active* definition may be attached: a draft configuration is not
  # yet endorsed by the club (its weights may not total 100), and an archived
  # one is history. Re-saving a row that already points at a now-archived
  # definition is fine — that is how old results stay readable.
  def definition_must_be_active_to_attach
    return unless will_save_change_to_assessment_definition_id?
    return if assessment_definition.nil?
    return if assessment_definition.active?

    errors.add(:assessment_definition, "must be active before it can be applied")
  end

  # Publishing means endorsing every configured category, not just some of them.
  # A draft may be partial (the same rule that lets a legacy draft be unrated).
  def definition_fully_scored_when_active
    return unless definition_based? && active?
    return if definition_fully_scored?

    errors.add(:base, "Score every category of the definition before publishing")
  end

  def clear_legacy_rating_fields
    self.reported_value = nil
    self.scale = nil
  end

  # A person may hold both profiles. Nobody rates themselves, whoever records it:
  # comparing the FK columns keeps this query-free, and `coach_profiles.person_id`
  # is unique — one CoachProfile per Person — so "the same person" is unambiguous.
  def coach_must_not_assess_their_own_player_profile
    return if coach_profile.blank? || player_profile.blank?
    return unless coach_profile.person_id == player_profile.person_id

    errors.add(:coach_profile, "cannot be the same person as the player being assessed")
  end
end
