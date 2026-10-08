class AddRequiresApprovalToOrganisationsAndGroups < ActiveRecord::Migration[8.1]
  def up
    add_column :organisations, :requires_approval, :boolean, default: false, null: false
    add_column :groups, :requires_approval, :boolean, default: false, null: false

    # A self-service join that awaits approval is a `pending` row, so the roster's
    # status vocabulary has to admit the state the model now declares. The old
    # constraint only knew `active` and `ended`.
    execute <<~SQL
      ALTER TABLE group_memberships
        DROP CONSTRAINT group_memberships_status,
        ADD CONSTRAINT group_memberships_status
        CHECK (status = ANY (ARRAY['pending', 'active', 'ended']))
    SQL
  end

  def down
    # Rollback cannot invent a legal status for a pending row, so they are ended —
    # the one transition that records the fact rather than pretending it away.
    execute "UPDATE group_memberships SET status = 'ended', left_at = COALESCE(left_at, CURRENT_TIMESTAMP) WHERE status = 'pending'"
    execute <<~SQL
      ALTER TABLE group_memberships
        DROP CONSTRAINT group_memberships_status,
        ADD CONSTRAINT group_memberships_status
        CHECK (status = ANY (ARRAY['active', 'ended']))
    SQL

    remove_column :groups, :requires_approval
    remove_column :organisations, :requires_approval
  end
end
