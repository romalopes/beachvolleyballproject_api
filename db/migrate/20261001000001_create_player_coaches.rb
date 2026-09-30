class CreatePlayerCoaches < ActiveRecord::Migration[8.1]
  def change
    create_table :player_coaches do |t|
      # Keyed on the *profiles*, not on Person and not on User. An assessment
      # names a `player_profile` and a `coach_profile`, so the relationship that
      # explains a coach's authority over a player has to name the same two
      # things — a relationship between two People could not say which of a
      # person's roles it described.
      t.references :player_profile, null: false, foreign_key: true
      t.references :coach_profile, null: false, foreign_key: true

      # A period, not a flag: `end_date IS NULL` means "still coaching". There is
      # deliberately no `status`/`active` column beside it — the two could then
      # disagree about whether the relationship is running, and there would be no
      # way to tell which one was right.
      t.date :start_date, null: false
      t.date :end_date

      t.timestamps
    end

    # At most one *open* relationship per pair, enforced by the database rather
    # than only by a model check: two open periods for the same pair would make
    # "who coaches this player now?" ambiguous. Ended periods are deliberately
    # unconstrained, which is what lets a relationship end and later resume as a
    # new period.
    add_index :player_coaches, [ :player_profile_id, :coach_profile_id ],
              unique: true,
              where: "end_date IS NULL",
              name: "index_player_coaches_single_current_per_pair"

    # The same period cannot be recorded twice. Distinct from the index above
    # because two *ended* periods for the same pair may legitimately start on
    # different days.
    add_index :player_coaches, [ :player_profile_id, :coach_profile_id, :start_date ],
              unique: true,
              name: "index_player_coaches_pair_and_start"

    # "The relationships running now" for one player, or for one coach, is the
    # query both detail screens ask, so each gets a covering index rather than a
    # sequential scan of a table that only ever grows.
    add_index :player_coaches, [ :player_profile_id, :end_date ],
              name: "index_player_coaches_on_player_and_end"
    add_index :player_coaches, [ :coach_profile_id, :end_date ],
              name: "index_player_coaches_on_coach_and_end"

    # An ended relationship cannot have ended before it started. Mirrored by
    # `PlayerCoach#end_date_not_before_start_date`, which produces a message a
    # coach can read; this constraint is the guard that survives a race.
    add_check_constraint :player_coaches,
                         "end_date IS NULL OR end_date >= start_date",
                         name: "player_coaches_end_after_start"
  end
end
