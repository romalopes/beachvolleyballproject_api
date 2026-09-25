# Phase 6 (Assessment Sessions), plan §2: which players belong to a group.
#
# The join references the PlayerProfile (domain identity), never the User, so
# players without an account can be grouped — the same reasoning as
# TrainingSessionParticipant.
#
# There is no status column: membership says "this player is in this squad", and
# anything more transient (invited / attended / absent) belongs to the session
# that observed it, not to the roster.
class CreateGroupMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :group_memberships do |t|
      t.references :group, null: false, foreign_key: true
      t.references :player_profile, null: false, foreign_key: true
      t.timestamps
    end

    # A player appears in a group once. Enforced here rather than only by
    # validation, so the roster cannot grow duplicate rows under concurrency.
    add_index :group_memberships, %i[group_id player_profile_id],
              unique: true,
              name: "index_group_memberships_on_group_and_player"
  end
end
