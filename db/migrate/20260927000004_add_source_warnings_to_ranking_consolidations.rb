class AddSourceWarningsToRankingConsolidations < ActiveRecord::Migration[8.1]
  def change
    # D21 (ratified): a consolidation never blocks over missing or incomplete
    # players. The reason it merged anyway is stored here so the record is
    # self-explanatory later, even if the source session changes afterwards —
    # it is part of the immutable snapshot, not recomputed on read.
    add_column :ranking_consolidations, :source_warnings, :jsonb, default: [], null: false
  end
end
