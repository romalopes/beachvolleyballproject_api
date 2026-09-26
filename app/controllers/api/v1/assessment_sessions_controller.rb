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

    unless authorized_to_create?(session_record)
      return render json: { error: "Forbidden" }, status: :forbidden
    end

    if session_record.save
      render json: { assessment_session: serialize(session_record) }, status: :created
    else
      render json: { errors: session_record.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    return refuse_edits unless authorized_to_manage?(@assessment_session)

    refuse_if_not_draft
    return if performed?

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
    return refuse_edits unless authorized_to_manage?(@assessment_session)

    refuse_if_not_draft
    return if performed?

    rows = Array(
      params.permit(players: [
        :player_profile_id, :inclusion, :missing_reason,
        { person: INLINE_PERSON_ATTRIBUTES }
      ])[:players]
    )
    return render json: { error: "No players supplied" }, status: :unprocessable_entity if rows.empty?

    created = []
    failed = []

    AssessmentSession.transaction do
      InlineParticipantResolver.new(created_by: Current.user).call(rows)

      rows.each do |row|
        participant = @assessment_session.participants.build(
          player_profile_id: row[:player_profile_id],
          inclusion: row[:inclusion] || "included",
          missing_reason: row[:missing_reason]
        )

        if participant.save
          created << participant
        else
          failed << { player_profile_id: row[:player_profile_id],
                      errors: participant.errors.full_messages }
        end
      end

      # All-or-nothing: a rejected row must not leave a half-built roster.
      raise ActiveRecord::Rollback if failed.any?
    end

    if failed.any?
      render json: { errors: failed }, status: :unprocessable_entity
    else
      render json: {
        assessment_session: serialize(@assessment_session.reload),
        added: created.size
      }, status: :created
    end
  end

  def remove_players
    return refuse_edits unless authorized_to_manage?(@assessment_session)

    refuse_if_not_draft
    return if performed?

    ids = Array(params[:player_profile_ids]).map(&:to_i)
    removed = @assessment_session.participants.where(player_profile_id: ids).destroy_all.size

    render json: { assessment_session: serialize(@assessment_session.reload), removed: removed }
  end

  # Save a whole score grid atomically. The request carries stable player and
  # category ids; totals and ranks are never accepted from the client.
  def scores
    return refuse_edits unless authorized_to_manage?(@assessment_session)

    refuse_if_not_draft
    return if performed?

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
    return refuse_edits unless authorized_to_manage?(@assessment_session)

    refuse_if_not_draft
    return if performed?

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

  # A coach may create a session only for the coach account represented by the
  # selected domain profile. Curators/admins may create sessions for any coach.
  def authorized_to_create?(session_record)
    return true if Current.user&.admin? || Current.user&.curator?

    account = session_record.coach_profile&.person&.account
    account.present? && account.user == Current.user
  end

  # Writes are the union of two roles, and content management alone is NOT one
  # of them: publishing ratings about a named player is a judgement, not a
  # catalogue edit, so a manager who is not the coach of record cannot rewrite
  # someone else's numbers.
  def authorized_to_manage?(session_record)
    return true if Current.user&.admin? || Current.user&.curator?
    return true if coach_of_record?(session_record)

    false
  end

  # The coach of record is the domain coach's linked account, not the creating
  # user: the coach may sign in from a different account than the one that
  # first created the session, and the rating belongs to the coach.
  def coach_of_record?(session_record)
    account = session_record.coach_profile.person&.account
    account.present? && account.user == Current.user
  end

  def refuse_edits
    render json: { error: "Forbidden" }, status: :forbidden
  end

  # The roster is only editable while the session is a draft. A published
  # session is archival: correcting it is a withdrawal, not a silent edit.
  def refuse_if_not_draft
    return if @assessment_session.draft?

    render json: { error: "Only draft sessions can be modified" },
           status: :unprocessable_entity
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
