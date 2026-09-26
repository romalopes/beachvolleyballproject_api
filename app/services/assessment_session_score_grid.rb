# Persists one coach's score grid for an assessment session atomically.
#
# The request names players and configured categories; this service owns every
# conversion and total. It creates or updates the session-scoped draft
# `Assessment` result and its category rows inside one transaction, so an
# invalid cell anywhere in the grid leaves the previous state untouched.
# Client-supplied totals or ranks are never accepted.
class AssessmentSessionScoreGrid
  class Error < StandardError
    attr_reader :errors

    def initialize(errors)
      @errors = Array(errors)
      super(@errors.join(", "))
    end
  end

  RATING_KEYS = %i[value score reported_value].freeze

  def initialize(session:, current_user:)
    @session = session
    @current_user = current_user
  end

  def call(rows)
    failures = []

    AssessmentSession.transaction do
      Array(rows).each { |row| persist_player(row, failures) }
      raise ActiveRecord::Rollback if failures.any?
    end

    raise Error, failures if failures.any?

    true
  end

  private

  attr_reader :session, :current_user

  def persist_player(row, failures)
    player_profile_id = param(row, :player_profile_id).to_i
    participant = session.participants.find_by(player_profile_id: player_profile_id)

    unless participant
      failures << "Player #{player_profile_id} is not on this session roster"
      return
    end

    if participant.excluded?
      failures << "#{player_name(participant)} is excluded from this session and cannot be scored"
      return
    end

    cells = Array(param(row, :category_scores) || param(row, :scores))
    if cells.empty?
      failures << "#{player_name(participant)} has no category scores supplied"
      return
    end

    assessment = session.assessments.find_or_initialize_by(player_profile_id: player_profile_id)
    if assessment.persisted? && !assessment.draft?
      failures << "#{player_name(participant)} result is #{assessment.status} and cannot be edited"
      return
    end

    assessment.coach_profile = session.coach_profile
    assessment.assessment_definition = session.assessment_definition
    assessment.created_by ||= current_user

    touched = false
    cells.each do |cell|
      category = category_for(param(cell, :assessment_category_id))
      unless category
        failures << "#{player_name(participant)} has a score for a category outside this definition"
        next
      end

      score_row = score_row_for(assessment, category.id)
      if blank_rating?(cell)
        touched = true if clear_score_row(assessment, score_row)
        next
      end

      score_row ||= assessment.assessment_category_scores.build(assessment_category: category)
      touched = true if apply_rating(score_row, cell, participant, failures)
    end

    return unless touched

    begin
      failures.concat(assessment.errors.full_messages) unless assessment.save
    rescue ActiveRecord::RecordInvalid => e
      failures.concat(e.record.errors.full_messages)
    end
  end

  def category_for(id)
    return if id.blank?

    session.assessment_definition.assessment_categories.find_by(id: id)
  end

  def score_row_for(assessment, category_id)
    assessment.assessment_category_scores.find do |row|
      row.assessment_category_id == category_id && row.criterion_id.nil?
    end
  end

  # A present but empty rating clears an existing cell. Omitted categories are
  # left alone, which is what makes a partial grid save safe.
  def blank_rating?(cell)
    RATING_KEYS.any? { |key| has_key?(cell, key) } &&
      RATING_KEYS.all? { |key| param(cell, key).blank? }
  end

  def clear_score_row(assessment, score_row)
    return false if score_row.nil?

    if score_row.persisted?
      score_row.destroy!
    else
      assessment.assessment_category_scores.delete(score_row)
    end
    true
  end

  def apply_rating(score_row, cell, participant, failures)
    label = "#{player_name(participant)} / #{score_row.assessment_category&.label || score_row.assessment_category_id}"

    if param(cell, :value).present?
      scale = param(cell, :scale).presence || score_row.scale.presence || RatingScale::DEFAULT_SCALE
      number = Integer(param(cell, :value).to_s, exception: false)
      unless number && RatingScale.legal_value?(number, scale: scale)
        failures << "#{label} value #{param(cell, :value)} is not a value on the #{scale} scale"
        return false
      end

      score_row.scale = scale
      score_row.reported_value = number
      score_row.score = RatingScale.to_score(number, scale: scale)
    elsif param(cell, :score).present?
      scale = param(cell, :scale).presence || score_row.scale.presence || RatingScale::DEFAULT_SCALE
      score = Integer(param(cell, :score).to_s, exception: false)
      unless score && score.between?(RatingScale::SCORE_MIN, RatingScale::SCORE_MAX)
        failures << "#{label} score must be between #{RatingScale::SCORE_MIN} and #{RatingScale::SCORE_MAX}"
        return false
      end

      reported = if param(cell, :reported_value).present?
                   Integer(param(cell, :reported_value).to_s, exception: false)
      else
                   RatingScale.reported_for(score, scale: scale)
      end
      unless reported && RatingScale.legal_value?(reported, scale: scale)
        failures << "#{label} reported value is not a value on the #{scale} scale"
        return false
      end

      score_row.scale = scale
      score_row.score = score
      score_row.reported_value = reported
    elsif param(cell, :reported_value).present?
      scale = param(cell, :scale).presence || score_row.scale.presence || RatingScale::DEFAULT_SCALE
      reported = Integer(param(cell, :reported_value).to_s, exception: false)
      unless reported && RatingScale.legal_value?(reported, scale: scale)
        failures << "#{label} reported value #{param(cell, :reported_value)} is not a value on the #{scale} scale"
        return false
      end

      score_row.scale = scale
      score_row.reported_value = reported
      score_row.score = RatingScale.to_score(reported, scale: scale)
    else
      failures << "#{label} must include a value, score, or reported_value"
      return false
    end

    score_row.notes = param(cell, :notes) if has_key?(cell, :notes)
    true
  end

  def player_name(participant)
    participant.player_profile.full_name.presence || "Player ##{participant.player_profile_id}"
  end

  def has_key?(source, key)
    return false unless source.respond_to?(:key?)

    source.key?(key) || source.key?(key.to_s)
  end

  def param(source, key)
    return unless source.respond_to?(:[])

    value = source[key]
    value.nil? ? source[key.to_s] : value
  end
end
