class CreateVideoReferences < ActiveRecord::Migration[8.1]
  def change
    create_table :video_references do |t|
      t.references :video, null: false, foreign_key: true

      # Polymorphic link to the contextual use of the video: Drill, Skill and,
      # later, TrainingSession/Tournament/etc. without another join table.
      t.references :referenced, polymorphic: true, null: false

      # Relevance window within the video, stored as integer seconds.
      t.integer :start_seconds
      t.integer :end_seconds

      t.string :title
      t.text :description
      t.integer :position

      t.timestamps
    end

    add_index :video_references, [ :referenced_type, :referenced_id, :position ],
              name: "index_video_references_on_referenced_and_position"

    # Timestamp sanity at the database level; NULLs are allowed (start-only
    # references and future uploaded videos without a known duration).
    change_table :video_references do |t|
      t.check_constraint "start_seconds IS NULL OR start_seconds >= 0",
                         name: "video_references_start_seconds_non_negative"
      t.check_constraint "end_seconds IS NULL OR end_seconds >= 0",
                         name: "video_references_end_seconds_non_negative"
      t.check_constraint "end_seconds IS NULL OR start_seconds IS NULL OR end_seconds > start_seconds",
                         name: "video_references_end_after_start"
    end
  end
end
