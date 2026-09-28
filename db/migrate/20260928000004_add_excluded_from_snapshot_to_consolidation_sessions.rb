class AddExcludedFromSnapshotToConsolidationSessions < ActiveRecord::Migration[8.1]
  def up
    # "Are this source's scores in the snapshot?" is a fact about the snapshot, and
    # the builder is the only thing that knows it at write time. It used to be
    # inferred from comparing a session's `updated_at` against the ranking's
    # publication time, which only holds while the source stays withdrawn: once a
    # withdrawn source is restored to published it falls out of that comparison and
    # the API starts claiming its (empty) snapshot is included.
    add_column :ranking_consolidation_sessions,
               :excluded_from_snapshot,
               :boolean,
               null: false,
               default: false

    backfill_excluded_sources
  end

  def down
    remove_column :ranking_consolidation_sessions, :excluded_from_snapshot
  end

  private

  # Rows written before this column existed were excluded exactly when the builder
  # snapshotted them empty *and* recorded a `source_session_withdrawn` warning. The
  # warning is the reliable signal: an empty snapshot on its own is ambiguous, since
  # a session may also be empty because nobody scored anybody (D21 never blocks).
  def backfill_excluded_sources
    withdrawn_ids = RankingConsolidation
                    .where.not(source_warnings: [])
                    .pluck(:id, :source_warnings)
                    .each_with_object([]) do |(consolidation_id, warnings), memo|
      warnings.filter_map { |w| w["assessment_session_id"] if w["reason"] == "source_session_withdrawn" }
              .each { |session_id| memo << [ consolidation_id, session_id ] }
    end

    return if withdrawn_ids.empty?

    withdrawn_ids.each do |consolidation_id, session_id|
      execute(<<~SQL.squish)
        UPDATE ranking_consolidation_sessions
        SET excluded_from_snapshot = TRUE
        WHERE ranking_consolidation_id = #{consolidation_id}
          AND assessment_session_id = #{session_id}
      SQL
    end
  end
end
