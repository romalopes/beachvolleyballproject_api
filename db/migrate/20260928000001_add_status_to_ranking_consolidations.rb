class AddStatusToRankingConsolidations < ActiveRecord::Migration[8.1]
  def up
    # A consolidation becomes a draft when it is built and freezes when it is
    # published, mirroring AssessmentSession. Until now a consolidation was
    # frozen the moment it was created, which meant a coach could not assemble a
    # club ranking from sessions that were still being scored.
    add_column :ranking_consolidations, :status, :string, default: "draft", null: false
    add_column :ranking_consolidations, :published_at, :datetime

    # Existing consolidations are club rankings already built from published
    # sessions and read as published. Backfilling them to "draft" would present
    # historical, in-use rankings as editable drafts, so they are marked
    # published and dated with their creation time.
    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          UPDATE ranking_consolidations
             SET status = 'published', published_at = created_at
        SQL
      end
    end

    add_index :ranking_consolidations, :status
    add_check_constraint :ranking_consolidations,
                         "status::text = ANY (ARRAY['draft'::character varying, 'published'::character varying]::text[])",
                         name: "ranking_consolidations_status"
  end

  def down
    remove_check_constraint :ranking_consolidations, name: "ranking_consolidations_status"
    remove_index :ranking_consolidations, :status
    remove_column :ranking_consolidations, :published_at
    remove_column :ranking_consolidations, :status
  end
end
