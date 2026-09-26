class Api::V1::AssessmentSessionsController < ApplicationController
  include ContentAuthorization

  # The inline-person allow-list is owned by the resolver, exactly as it is in
  # TrainingSessionsController, so the permit list and the consumer cannot drift.
  INLINE_PERSON_ATTRIBUTES = InlineParticipantResolver::PERSON_ATTRIBUTES

  # A session is a shared coaching artefact, not a private note, so reads use
  # the same gate as the rest of the shared schedule.
  before_action :require_training_manager!
  before_action :set_assessment_session,
                only: %i[show update add_players remove_players scores publish ranking]

  def index
    sessions = AssessmentSession.ordered
                       .includes(:assessment_definition, :coach_profile, :group,
                                 participants: :player_profile,
                                 assessments: { assessment_category_scores: :assessment_category })
    render json: { assessment_sessions: sessions.map { |s| serialize(s) } }
  end

  def show
    render json: { assessment_session: serialize(@assessment_session) }
  end

  def create
    session_record = AssessmentSession.new(session_params)
    session_record.created_by = Current.user

    unless oversight_or_coach_of_record?(session_record.coach_profile)
      return render json: { error: "Forbidden" }, status: :forbidden
    end

    if session_record.save
      render json: { assessment_session: serialize(session_record) }, status: :created
    else
      render json: { errors: session_record.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    return unless authorize_draft_edit!(@assessment_session)

    if @assessment_session.update(session_params)
      render json: { assessment_session: serialize(@assessment_session) }
    else
      render json: { errors: @assessment_session.errors.full_messages },
             status: :unprocessable_entity
    end
  end

  # Add players to the roster, accepting both an existing `player_profile_id`
  # and a nested `person:` for someone who has no record yet. Resolution is
  # shared with training sessions (InlineParticipantResolver) so the identity
  # rules cannot drift between the two flows.
  def add_players
    return unless authorize_draft_edit!(@assessment_session)

    rows = Array(
      params.permit(players: [
        :player_profile_id, :inclusion, :missing_reason,
        { person: INLINE_PERSON_ATTRIBUTES }
      ])[:players]
    )
    return render json: { error: "No players supplied" }, status: :unprocessable_entity if rows.empty?

    result = AssessmentSessionRoster.new(
      session: @assessment_session,
      current_user: Current.user
    ).call(rows)

    if result.failed.any?
      render json: { errors: result.failed }, status: :unprocessable_entity
    else
      render json: {
        assessment_session: serialize(@assessment_session.reload),
        added: result.created.size
      }, status: :created
    end
  end

  def remove_players
    return unless authorize_draft_edit!(@assessment_session)

    ids = Array(params[:player_profile_ids]).map(&:to_i)
    removed = @assessment_session.participants.where(player_profile_id: ids).destroy_all.size

    render json: { assessment_session: serialize(@assessment_session.reload), removed: removed }
  end

  # Save a whole score grid atomically. The request carries stable player and
  # category ids; totals and ranks are never accepted from the client.
  def scores
    return unless authorize_draft_edit!(@assessment_session)

    rows = Array(params[:scores])
    if rows.empty?
      return render json: { error: "No scores supplied" }, status: :unprocessable_entity
    end

    AssessmentSessionScoreGrid.new(
      session: @assessment_session,
      current_user: Current.user
    ).call(rows)

    render json: { assessment_session: serialize(@assessment_session.reload) }
  rescue AssessmentSessionScoreGrid::Error => e
    render json: { errors: e.errors }, status: :unprocessable_entity
  end

  # Publishing is the session's authority (S3): it validates that every
  # included player is complete, then promotes the session and its draft result
  # rows in one transaction (S2). An incomplete roster is a 422, never a
  # partial publish.
  def publish
    return unless authorize_draft_edit!(@assessment_session)

    ranking = AssessmentSessionRanking.new(@assessment_session).call
    if ranking[:incomplete].any?
      messages = ranking[:incomplete].map do |row|
        "#{row[:player_name]} is missing #{row[:missing_category_ids].size} category score(s)"
      end
      return render json: { errors: [ "Score every included player before publishing" ] + messages },
                    status: :unprocessable_entity
    end

    AssessmentSession.transaction do
      @assessment_session.update!(status: "published", published_at: Time.current)
      @assessment_session.assessments.where(status: "draft").find_each do |assessment|
        assessment.update!(status: "active")
      end
    end

    render json: { assessment_session: serialize(@assessment_session.reload) }
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  # Server-side ranking over complete rows only. Missing scores are reported
  # explicitly and never coerced to zero (D14); ties use standard competition
  # ranking (D15).
  def ranking
    payload = AssessmentSessionRanking.new(@assessment_session).call

    render json: {
      assessment_session: serialize_session_identity(@assessment_session),
      ranking: payload[:ranking],
      incomplete: payload[:incomplete],
      excluded: payload[:excluded]
    }
  end

  def set_assessment_session
    @assessment_session = AssessmentSession.find(params[:id])
  end

  # Writes are the union of two roles — oversight (curator/admin) or the coach
  # of record — and only while the session is a draft. Content management alone
  # is NOT enough: publishing ratings about a named player is a judgement, not
  # a catalogue edit. A published session is archival, so correcting it is a
  # withdrawal, not a silent edit.
  #
  # Returns true when the action may proceed; renders 403/422 and returns false
  # otherwise, so each action is a single `return unless ...` line instead of
  # the old guard-plus-`performed?` dance.
  def authorize_draft_edit!(session_record)
    unless oversight_or_coach_of_record?(session_record.coach_profile)
      render json: { error: "Forbidden" }, status: :forbidden
      return false
    end

    unless session_record.draft?
      render json: { error: "Only draft sessions can be modified" },
             status: :unprocessable_entity
      return false
    end

    true
  end

  def session_params
    params.expect(assessment_session: %i[
      name assessment_definition_id coach_profile_id group_id scheduled_on notes
    ])
  end

  def serialize(session_record)
    ranking = AssessmentSessionRanking.new(session_record).call
    results = (ranking[:ranking] + ranking[:incomplete] + ranking[:excluded])
                .index_by { |row| row[:player_profile_id] }

    {
      id: session_record.id,
      name: session_record.name,
      status: session_record.status,
      status_label: session_record.status.capitalize,
      scheduled_on: session_record.scheduled_on,
      notes: session_record.notes,
      published_at: session_record.published_at,
      created_by_id: session_record.created_by_id,
      coach_profile_id: session_record.coach_profile_id,
      coach_profile: {
        id: session_record.coach_profile_id,
        full_name: session_record.coach_profile.full_name
      },
      group_id: session_record.group_id,
      assessment_definition: serialize_definition(session_record.assessment_definition),
      group: session_record.group && { id: session_record.group.id, name: session_record.group.name },
      ranking: {
        ranking: ranking[:ranking],
        incomplete: ranking[:incomplete],
        excluded: ranking[:excluded]
      },
      participants: session_record.participants.map do |participant|
        {
          id: participant.id,
          player_profile_id: participant.player_profile_id,
          player_name: participant.player_profile.full_name,
          inclusion: participant.inclusion,
          missing_reason: participant.missing_reason,
          result: results[participant.player_profile_id]
        }
      end
    }
  end

  def serialize_session_identity(session_record)
    {
      id: session_record.id,
      name: session_record.name,
      status: session_record.status,
      scheduled_on: session_record.scheduled_on,
      assessment_definition: serialize_definition(session_record.assessment_definition)
    }
  end

  def serialize_definition(definition)
    return nil if definition.nil?

    {
      id: definition.id,
      name: definition.name,
      status: definition.status,
      assessment_categories: definition.assessment_categories.order(:position).map do |category|
        { id: category.id, label: category.label, weight: category.weight, position: category.position }
      end
    }
  end
end
