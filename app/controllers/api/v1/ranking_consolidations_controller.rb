# Phase 4 (Ranking Consolidation), plan §8: immutable snapshots merging
# several coaches' published session results into one club ranking.
#
# Reads use the training-manager gate like sessions (the payload names players
# and scores). Creation additionally requires a content creator (coach/admin):
# a curator may view but never mint a club judgement. There is no update or
# destroy — a consolidation is archival (D24); corrections are new records.
class Api::V1::RankingConsolidationsController < ApplicationController
  include ContentAuthorization

  before_action :require_training_manager!
  before_action :require_content_creator!, only: %i[create]
  before_action :set_consolidation, only: %i[show]

  def index
    consolidations = RankingConsolidation.ordered
                                         .includes(:assessment_definition, :created_by,
                                                   consolidation_sessions: :assessment_session,
                                                   rows: { player_profile: :person })
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

  private

  def set_consolidation
    @consolidation = RankingConsolidation.includes(:assessment_definition, :created_by,
                                                   consolidation_sessions: :assessment_session,
                                                   rows: { player_profile: :person })
                                         .find(params[:id])
  end

  def consolidation_params
    params.expect(ranking_consolidation: [ :name, :notes, :assessment_definition_id,
                                           { assessment_session_ids: [] } ])
  end

  def serialize(consolidation)
    sessions = consolidation.consolidation_sessions.sort_by(&:id).map do |join|
      session = join.assessment_session
      {
        assessment_session_id: join.assessment_session_id,
        name: session&.name,
        coach_name: session&.coach_profile&.full_name,
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
      created_by_id: consolidation.created_by_id,
      assessment_definition: {
        id: consolidation.assessment_definition.id,
        name: consolidation.assessment_definition.name
      },
      session_count: sessions.size,
      player_count: rows.size,
      assessment_sessions: sessions,
      rows: rows
    }
  end
end
