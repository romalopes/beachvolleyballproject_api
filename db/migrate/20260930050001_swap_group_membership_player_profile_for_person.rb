# One PlayerProfile's membership of a Group -> one Person's membership of a Group.
#
# The roster is keyed on Person rather than PlayerProfile (plan §2.2) for the same
# reason OrganisationMembership is: a squad has to be able to contain a coach, a
# parent or a volunteer who never registered as a player at all. In the rehearsal
# data that was not hypothetical — the one group's creator had no player profile,
# so under the old column they could not be given an owner membership at all.
#
# `player_profiles.person_id` is NOT NULL and uniquely indexed, so one profile
# maps to exactly one person. That makes this a lossless 1:1 rewrite: the new
# unique (group_id, person_id) index is satisfied without any collision handling.
class SwapGroupMembershipPlayerProfileForPerson < ActiveRecord::Migration[8.1]
  def up
    add_column :group_memberships, :person_id, :bigint
    add_index :group_memberships, :person_id

    execute <<~SQL
      UPDATE group_memberships gm
      SET person_id = pp.person_id
      FROM player_profiles pp
      WHERE pp.id = gm.player_profile_id
    SQL

    # Gates the migration rather than trusting the join. player_profiles.person_id
    # is NOT NULL, so a row can only survive this with a player_profile_id that
    # matches no profile — which would otherwise become a NOT NULL failure
    # somewhere less legible than here.
    unresolved = select_value(<<~SQL).to_i
      SELECT COUNT(*) FROM group_memberships WHERE person_id IS NULL
    SQL
    if unresolved.positive?
      raise ActiveRecord::MigrationError,
            "#{unresolved} group_memberships rows have no resolvable person; " \
            "the roster was not rewritten"
    end

    remove_index :group_memberships,
                 name: "index_group_memberships_on_group_and_player"
    remove_index :group_memberships,
                 name: "index_group_memberships_on_player_profile_id"
    remove_column :group_memberships, :player_profile_id

    change_column_null :group_memberships, :person_id, false
    add_index :group_memberships, %i[group_id person_id],
              unique: true, name: "index_group_memberships_on_group_and_person"
    add_foreign_key :group_memberships, :people
  end

  def down
    remove_foreign_key :group_memberships, :people
    remove_index :group_memberships,
                 name: "index_group_memberships_on_group_and_person"

    add_column :group_memberships, :player_profile_id, :bigint
    # Reversible only for people who still have a profile. A squad member added
    # precisely because they had none cannot be expressed in the old column, so
    # those rows are dropped rather than left pointing at a profile that is not
    # there — the roster is the thing being restored, and an ownerless group is
    # the one state worth never restoring silently.
    execute <<~SQL
      DELETE FROM group_memberships gm
      WHERE NOT EXISTS (
        SELECT 1 FROM player_profiles pp WHERE pp.person_id = gm.person_id
      )
    SQL

    execute <<~SQL
      UPDATE group_memberships gm
      SET player_profile_id = pp.id
      FROM player_profiles pp
      WHERE pp.person_id = gm.person_id
    SQL

    change_column_null :group_memberships, :player_profile_id, false
    remove_index :group_memberships, :person_id
    remove_column :group_memberships, :person_id

    add_index :group_memberships, %i[group_id player_profile_id],
              unique: true, name: "index_group_memberships_on_group_and_player"
    add_index :group_memberships, :player_profile_id
  end
end
