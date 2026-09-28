class AddRecalculationToRankingConsolidations < ActiveRecord::Migration[8.1]
  def change
    # A published consolidation is frozen (D24), and a session withdrawn after
    # publication does not change it. These columns record an explicit, supervised
    # correction instead: `recalculated_at` is when the snapshot was last rebuilt
    # from live sources, and `recalculated_by_id` who authorised it.
    #
    # `published_at` is deliberately NOT touched by a recalculation — it answers
    # "when did this become the club's result", which a later correction does not
    # change. The effective "computed at" is COALESCE(recalculated_at,
    # published_at), and comparing that against a source's withdrawal time is what
    # tells a coach whether a withdrawn session is already excluded or still counted.
    add_column :ranking_consolidations, :recalculated_at, :datetime
    add_column :ranking_consolidations, :recalculated_by_id, :bigint

    add_index :ranking_consolidations, :recalculated_by_id
    add_foreign_key :ranking_consolidations, :users, column: :recalculated_by_id
  end
end
