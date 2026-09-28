class AddWithdrawnToRankingConsolidations < ActiveRecord::Migration[8.1]
  def change
    # A withdrawn consolidation is a club ranking the author has retracted, not a
    # deleted one. It stays in the record so the retraction is visible and
    # reversible: an admin can restore it to draft or published, which a hard
    # delete could never allow.
    #
    # The previous constraint is dropped first because the default 'draft' is
    # already inside the new set, so existing rows need no data backfill.
    remove_check_constraint :ranking_consolidations, name: "ranking_consolidations_status"

    add_check_constraint :ranking_consolidations,
                         "status::text = ANY (ARRAY['draft'::character varying, 'published'::character varying, 'withdrawn'::character varying]::text[])",
                         name: "ranking_consolidations_status"
  end
end
