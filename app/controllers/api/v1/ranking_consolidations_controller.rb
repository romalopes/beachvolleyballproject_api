# Phase 4 (Ranking Consolidation), plan §8: snapshots merging several coaches'
# session results into one club ranking.
#
# Reads use the training-manager gate like sessions (the payload names players
# and scores). Creation additionally requires a content creator (coach/admin):
# a curator may view but never mint a club judgement.
#
# There is no update and no destroy. A consolidation is assembled as a draft —
# its source sessions may still be being scored — and publishing freezes it
# (D24); corrections are new records. Publishing requires oversight or the
# author, mirroring the session rule: a curator who may read a club ranking is
# not thereby the person who signs it off.
class Api::V1::RankingConsolidationsController < ApplicationController
  include ContentAuthorization

  before_action :require_training_manager!
  before_action :require_content_creator!, only: %i[create]
  before_action :set_consolidation,
                only: %i[show update destroy publish withdraw restore recalculate]
  before_action :authorize_publisher!, only: %i[publish]

  def index
    consolidations = RankingConsolidation.ordered
                                         .includes(:assessment_definition, :created_by,
                                                   consolidation_sessions: :assessment_session,
                                                   rows: :player_profile)
    render json: { ranking_consolidations: consolidations.map { |c| serialize(c) } }
  end

  def show
    render json: { ranking_consolidation: serialize(@consolidation) }
  end

  def create
    definition = AssessmentDefinition.find_by(id: consolidation_params[:assessment_definition_id])
    unless definition
      return render json: { errors: [ "Assessment definition was not found" ] }, status: :not_found
    end

    begin
      consolidation = RankingConsolidationBuilder.new(
        assessment_definition: definition,
        session_ids: Array(consolidation_params[:assessment_session_ids]),
        name: consolidation_params[:name],
        notes: consolidation_params[:notes],
        current_user: Current.user
      ).call
    rescue RankingConsolidationBuilder::Error => e
      return render json: { errors: e.errors }, status: :unprocessable_entity
    end

    render json: { ranking_consolidation: serialize(consolidation.reload) }, status: :created
  end

  # Edit a consolidation's own metadata. Its source sessions and the snapshot
  # derived from them are deliberately not editable: a draft re-derives from its
  # sources on every publish, so changing the ranking means changing the sources —
  # a new consolidation, or withdrawing this one.
  def update
    return if @consolidation.withdrawn? && !authorize_admin_only!(@consolidation)
    return unless authorize_consolidation_edit!

    if @consolidation.update(consolidation_update_params)
      render json: { ranking_consolidation: serialize(@consolidation.reload) }
    else
      render json: { errors: @consolidation.errors.full_messages },
             status: :unprocessable_entity
    end
  end

  # A draft is discardable by its author, a curator or an admin. A published one
  # is the club's official ranking, so deleting it is admin-only and is the escape
  # hatch for a ranking that should never have been published; `withdraw` is the
  # ordinary, reversible retraction.
  def destroy
    return unless authorize_consolidation_destroy!

    @consolidation.destroy!

    render json: { message: "Ranking consolidation deleted", id: params[:id] }
  end

  # Retract a published consolidation. Its rows and snapshot are kept, so history
  # does not lose the record that this ranking once existed — only its claim to be
  # current.
  def withdraw
    return unless authorize_withdraw!(@consolidation)

    @consolidation.update!(status: "withdrawn", published_at: nil)

    render json: { ranking_consolidation: serialize(@consolidation.reload) }
  end

  # Rebuild a published ranking so a source withdrawn *after* it was published stops
  # contributing. Oversight only (curator/admin): this rewrites a result other people
  # may already have acted on, which is why it is not left to the author.
  #
  # `published_at` is preserved; `recalculated_at` records the correction.
  def recalculate
    return unless authorize_oversight!

    RankingConsolidationRecalculator.new(@consolidation, current_user: Current.user).call

    render json: { ranking_consolidation: serialize(@consolidation.reload) }
  rescue RankingConsolidationRecalculator::Error => e
    render json: { errors: e.errors }, status: :unprocessable_entity
  end

  # Bring a withdrawn consolidation back. Admin only. `to_status` is explicit, and
  # `published` re-derives the snapshot from the current sources rather than
  # reviving the frozen one.
  def restore
    return unless authorize_admin_only!(@consolidation)

    to_status = params.require(:to_status)
    RankingConsolidationRestorer.new(@consolidation, to_status: to_status).call

    render json: { ranking_consolidation: serialize(@consolidation.reload) }
  rescue RankingConsolidationRestorer::Error => e
    render json: { errors: e.errors }, status: :unprocessable_entity
  rescue ActionController::ParameterMissing
    render json: { errors: [ "to_status is required" ] }, status: :unprocessable_entity
  end

  # Freeze a draft as the club's official ranking. Refused with 422 while any
  # source session is still a draft, naming the sessions so the coach knows what
  # to finish. The snapshot is re-derived first (see RankingConsolidationPublisher),
  # so what is published is what the published sessions say now.
  def publish
    RankingConsolidationPublisher.new(@consolidation).call
    render json: { ranking_consolidation: serialize(@consolidation.reload) }
  rescue RankingConsolidationPublisher::Error => e
    render json: { errors: e.errors }, status: :unprocessable_entity
  end

  private

  # Oversight (curator/admin) or the coach who built it. Being able to read a
  # club ranking is not the same authority as signing it off.
  def authorize_publisher!
    return if @consolidation.nil?
    return if Assessment.oversight?(Current.user)
    return if @consolidation.created_by_id.present? && @consolidation.created_by_id == Current.user&.id

    render json: { error: "Forbidden" }, status: :forbidden
  end

  # Drafts are editable by the author, a curator or an admin. A published
  # consolidation is archival, so its metadata is frozen too: correcting it means
  # withdrawing and rebuilding, never a silent edit of history.
  def authorize_consolidation_edit!
    unless oversight? || record_creator?(@consolidation)
      render json: { error: "Forbidden" }, status: :forbidden
      return false
    end

    unless @consolidation.draft?
      render json: { error: "Only draft rankings can be edited" },
             status: :unprocessable_entity
      return false
    end

    true
  end

  def authorize_consolidation_destroy!
    return authorize_admin_only!(@consolidation) if @consolidation.withdrawn?
    return authorize_admin_delete! if @consolidation.published?

    authorize_draft_owner!(@consolidation)
  end

  # Only the descriptive fields. `assessment_definition_id` and the source
  # sessions are excluded on purpose: a consolidation is a merge over a fixed set
  # of sessions under one rubric, and swapping either underneath the snapshot
  # would make the record describe a merge it never performed.
  def consolidation_update_params
    params.expect(ranking_consolidation: %i[name notes])
  end


  def set_consolidation
    @consolidation = RankingConsolidation.includes(:assessment_definition, :created_by,
                                                   consolidation_sessions: :assessment_session,
                                                    rows: :player_profile)
                                         .find(params[:id])
  end

  def consolidation_params
    params.expect(ranking_consolidation: [ :name, :notes, :assessment_definition_id,
                                           { assessment_session_ids: [] } ])
  end

  # Recalculating is oversight work — it rewrites a result the club may already have
  # acted on — so it is curator/admin only, not the author's call even when they built
  # the ranking. A coach can withdraw their own session, but rewriting a published
  # result on their own authority is not something they can do silently.
  def authorize_oversight!
    return true if oversight?

    render json: { error: "Forbidden" }, status: :forbidden
    false
  end

  # The gate for the UI's "Recalculate" button, reported separately from
  # `recalculable` so a coach is not shown an action that would be refused.
  def caller_may_recalculate?(consolidation)
    consolidation.recalculable? && oversight?
  end

  def serialize(consolidation)
    # D21: per-session reasons a source session contributed fewer ranked rows.
    # Keyed by session id so the table can badge exactly the sessions at fault.
    warnings_by_session = consolidation.source_warnings.index_by { |w| w["assessment_session_id"] }
    # Every source the merge skipped, whatever state that source is in now. This must
    # not be narrowed to the withdrawn ones: a source excluded while withdrawn and
    # since restored is still missing from the snapshot, and would otherwise be
    # reported as included while contributing nothing.
    excluded_ids = consolidation.excluded_join_ids

    sessions = consolidation.consolidation_sessions.sort_by(&:id).map do |join|
      session = join.assessment_session
      warning = warnings_by_session[join.assessment_session_id]
      {
        assessment_session_id: join.assessment_session_id,
        name: session&.name,
        coach_name: session&.coach_profile&.full_name,
        # Carried so the UI can mark an unfinished source and the publish gate can
        # say which session is holding a draft back.
        status: session&.status,
        status_label: session&.status&.capitalize,
        # Present only for a withdrawn source: when its author retracted it. The UI
        # compares this against the ranking's `computed_at` to tell "already
        # excluded" from "still counted" — something live status alone cannot answer,
        # because a source withdrawn *after* publication is still in the numbers.
        withdrawn_at: session&.withdrawn? ? session.updated_at : nil,
        # Whether this session's scores are actually in the figures on screen, taken
        # from the snapshot row rather than from live status. A source the merge
        # skipped keeps reporting `false` even after it is restored to published,
        # which is the point: until the ranking is recalculated its scores really
        # are missing, and saying otherwise would hide a stale result.
        included_in_ranking: !excluded_ids.include?(join.assessment_session_id),
        incomplete_count: warning ? warning["incomplete_count"] : 0,
        incomplete_players: warning ? warning["incomplete_players"] : [],
        ranking_snapshot: join.ranking_snapshot
      }
    end

    rows = consolidation.rows.sort_by { |row| [ row.rank || 999_999, row.player_profile_id ] }.map do |row|
      {
        player_profile_id: row.player_profile_id,
        player_name: row.player_profile.full_name.presence || "Player ##{row.player_profile_id}",
        coach_scores: row.scores_by_session,
        coverage: row.coverage,
        average_score: row.average_score,
        rank: row.rank
      }
    end

    {
      id: consolidation.id,
      name: consolidation.name,
      notes: consolidation.notes,
      status: consolidation.status,
      status_label: consolidation.status_label,
      published_at: consolidation.published_at,
      created_by_id: consolidation.created_by_id,
      assessment_definition: {
        id: consolidation.assessment_definition.id,
        name: consolidation.assessment_definition.name
      },
      session_count: sessions.size,
      player_count: rows.size,
      # The gate the UI needs to decide whether to offer "Publish", and to say why
      # not. Without it a draft looks identical to a finished ranking.
      unpublished_session_count: sessions.count { |s| s[:status] == "draft" },
      # The gate for the "Recalculate" action: a published ranking with a source that
      # was withdrawn after it was frozen. Without it the UI would have to infer
      # that from live status, and would offer an action with nothing to correct.
      recalculable: consolidation.recalculable?,
      # Whether the *caller* may do it. The action itself refuses, but hiding it is
      # what keeps a coach from being offered something they cannot do.
      can_recalculate: caller_may_recalculate?(consolidation),
      # Withdrawn sources are excluded from the ranking rather than blocking it, so
      # the UI reports them separately: the coach is told which sessions are left
      # out, without being told the ranking is unfinished.
      withdrawn_session_count: sessions.count { |s| s[:status] == "withdrawn" },
      # Split by *when* the retraction happened, because for a published ranking the
      # two cases are different facts: a source withdrawn before it was computed is
      # already out of the numbers, while one withdrawn afterwards is still counted
      # until the ranking is explicitly recalculated.
      stale_withdrawn_session_count: consolidation.stale_withdrawn_source_sessions.size,
      excluded_withdrawn_session_count: consolidation.excluded_withdrawn_source_sessions.size,
      # Sources that were excluded by the merge and have since been restored to
      # published. They are scoring again but the frozen ranking is not using them,
      # so it under-reports until it is recalculated.
      restored_session_count: consolidation.restored_source_sessions.size,
      # When these figures were computed, and whether they were ever corrected.
      computed_at: consolidation.computed_at,
      recalculated_at: consolidation.recalculated_at,
      recalculated_by_id: consolidation.recalculated_by_id,
      source_warnings: consolidation.source_warnings,
      assessment_sessions: sessions,
      rows: rows
    }
  end
end
