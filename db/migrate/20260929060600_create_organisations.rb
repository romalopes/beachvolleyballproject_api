class CreateOrganisations < ActiveRecord::Migration[8.1]
  def change
    create_table :organisations do |t|
      # A self-reference, so the federation tree is data rather than four separate
      # tables. Depth is unbounded and nothing downstream may assume a fixed number
      # of levels.
      t.references :parent_organisation, null: true,
                                    foreign_key: { to_table: :organisations }
      t.string :name, null: false
      t.string :slug, null: false
      # A free-form classification. Deliberately not load-bearing: the hierarchy is
      # driven by parent/child, never by branching on the type, so a club and an
      # academy behave identically and new types need no code change.
      t.string :organisation_type, null: false, default: "other"
      t.text :description
      # Archive-not-delete, matching Group and AssessmentSession. A `status` enum
      # rather than an `archived_at` column, so it is consistent with every other
      # lifecycle in the project and the state is always queryable in one place.
      t.string :status, null: false, default: "active"
      # Person, not User: an organisation is recorded by whoever represents it, and
      # a Person is the domain identity whether or not they have an account.
      t.references :created_by_person, null: true, foreign_key: { to_table: :people }

      t.timestamps
    end

    # Same case-insensitive uniqueness as Group, so two organisations cannot differ
    # only by capitalisation.
    add_index :organisations, "lower((name)::text)",
              name: "index_organisations_on_lower_name", unique: true
    add_index :organisations, :slug, unique: true
    add_index :organisations, :organisation_type
    add_index :organisations, :status

    add_check_constraint :organisations,
                         "status::text = ANY (ARRAY['active'::character varying::text, " \
                         "'archived'::character varying::text])",
                         name: "organisations_status"
  end
end
