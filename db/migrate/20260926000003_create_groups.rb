# Phase 6 (Assessment Sessions), plan S1/§2: a named set of players a session can
# be run against — "U19 squad", "Monday group".
#
# A group is a *selection aid*, not an authorization boundary: it answers "who is
# in this squad?" so a coach does not re-pick twenty players for every session.
# Membership confers nothing on its own, which is why the join carries no status
# and why a group has no `owner`-style hard rule beyond who recorded it.
#
# Archive-not-delete, matching every other catalogue model in this project: a
# group that has been used to run sessions is history, so it becomes `archived`
# and stays readable.
class CreateGroups < ActiveRecord::Migration[8.1]
  def change
    create_table :groups do |t|
      t.references :created_by, foreign_key: { to_table: :users }
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.string :visibility, null: false, default: "shared"
      t.string :status, null: false, default: "active"
      t.timestamps
    end

    add_index :groups, :slug, unique: true
    add_index :groups, :name
    add_index :groups, :status
    add_index :groups, :visibility
    # Case-insensitive uniqueness, the same functional-index idiom
    # `video_tags` uses: the model compares case-insensitively, so the database
    # has to as well or the two rules disagree.
    add_index :groups, "lower((name)::text)", unique: true,
              name: "index_groups_on_lower_name"

    add_check_constraint :groups, "visibility IN ('shared', 'private')",
                         name: "groups_visibility"
    add_check_constraint :groups, "status IN ('active', 'archived')",
                         name: "groups_status"
  end
end
