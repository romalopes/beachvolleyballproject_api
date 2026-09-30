# Give a GroupMembership an owner, and a way to leave.
#
# Two gaps, both required by the plan and neither of them obvious from the schema:
#
# * There was no `role` column at all, so §2.6's "ownership has exactly one source
#   of truth" had nowhere to live. `Group#owner?` was reading `created_by_id`,
#   which is audit data. This adds the role and moves ownership onto it.
# * There was no `status` column, so §2.5's "memberships are ended, never
#   destroyed" was not representable — it only held by accident. Note this does
#   NOT re-add the invited/confirmed/attended vocabulary the old model comment
#   rejected: that reasoning still holds and attendance stays on the session that
#   observed it. Leaving a squad, though, is a fact about the roster, not evidence
#   about one session, so it belongs here as `ended` + `left_at`.
#
# `status` is deliberately narrower than OrganisationMembership's (no `pending`,
# no `suspended`): a squad roster has no use for them yet, and a check constraint
# is cheap to widen when there is a reason to.
class AddOwnershipAndLifecycleToGroupMemberships < ActiveRecord::Migration[8.1]
  ROLES = %w[owner coach member].freeze
  STATUSES = %w[active ended].freeze

  def up
    add_column :group_memberships, :role, :string, null: false, default: "member"
    add_column :group_memberships, :status, :string, null: false, default: "active"
    add_column :group_memberships, :joined_at, :datetime
    add_column :group_memberships, :left_at, :datetime

    # The row's own creation is the join date; there is no earlier truth for it.
    execute "UPDATE group_memberships SET joined_at = created_at WHERE joined_at IS NULL"

    # The creator is the owner, by the same rule the table used before. Two passes,
    # because the creator is often *not* on the roster: in the rehearsal data the
    # one group's creator had no membership at all, so a single "promote" pass would
    # have left that group with no owner and nothing able to manage it. Person-keyed
    # membership is what makes the second pass possible — an owner no longer needs
    # a player profile to exist.
    # `execute` returns a PG::Result, not a row count, so each backfill is wrapped
    # in a data-modifying CTE and counted by the outer SELECT. One statement, and
    # the number reported is genuinely the number of rows changed.
    promoted = select_value(<<~SQL).to_i
      WITH promoted AS (
        UPDATE group_memberships gm
        SET role = 'owner'
        FROM groups g
        JOIN accounts a ON a.user_id = g.created_by_id
        WHERE gm.group_id = g.id
          AND gm.person_id = a.person_id
        RETURNING gm.id
      )
      SELECT COUNT(*) FROM promoted
    SQL
    say "promoted #{promoted} existing membership(s) to owner"

    inserted = select_value(<<~SQL).to_i
      WITH added AS (
        INSERT INTO group_memberships
          (group_id, person_id, role, status, joined_at, created_at, updated_at)
        SELECT g.id, a.person_id, 'owner', 'active', g.created_at, now(), now()
        FROM groups g
        JOIN accounts a ON a.user_id = g.created_by_id
        WHERE g.created_by_id IS NOT NULL
          AND NOT EXISTS (
            SELECT 1 FROM group_memberships gm
            WHERE gm.group_id = g.id AND gm.person_id = a.person_id
          )
        RETURNING id
      )
      SELECT COUNT(*) FROM added
    SQL
    say "added #{inserted} owner membership(s) for creators who were not on the roster"

    # Reported rather than guessed at: a group whose creator has no account cannot
    # be given an owner by this migration and needs an admin to assign one.
    orphans = select_value(<<~SQL).to_i
      SELECT COUNT(*) FROM groups g
      WHERE NOT EXISTS (
        SELECT 1 FROM group_memberships gm
        WHERE gm.group_id = g.id AND gm.role = 'owner'
      )
    SQL
    say "WARNING: #{orphans} group(s) still have no owner and need one assigned" if orphans.positive?

    add_index :group_memberships, :group_id, unique: true,
              where: "role = 'owner' AND status = 'active'",
              name: "index_group_memberships_single_active_owner"

    add_check_constraint :group_memberships,
                         "role::text = ANY (ARRAY['owner', 'coach', 'member'])",
                         name: "group_memberships_role"
    add_check_constraint :group_memberships,
                         "status::text = ANY (ARRAY['active', 'ended'])",
                         name: "group_memberships_status"
    # `left_at` belongs to `ended` and to nothing else, so the two can never
    # disagree about whether somebody actually left. Mirrors
    # organisation_memberships (§4.5).
    add_check_constraint :group_memberships,
                         "left_at IS NULL OR (status = 'ended' AND left_at IS NOT NULL)",
                         name: "group_memberships_left_at_when_ended"
  end

  def down
    remove_check_constraint :group_memberships, name: "group_memberships_left_at_when_ended"
    remove_check_constraint :group_memberships, name: "group_memberships_status"
    remove_check_constraint :group_memberships, name: "group_memberships_role"
    remove_index :group_memberships, name: "index_group_memberships_single_active_owner"

    remove_column :group_memberships, :left_at
    remove_column :group_memberships, :joined_at
    remove_column :group_memberships, :status
    remove_column :group_memberships, :role
  end
end
