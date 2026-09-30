class AddAcronymToOrganisations < ActiveRecord::Migration[8.1]
  def change
    add_column :organisations, :acronym, :string

    # Nullable on purpose: existing rows have no acronym, and not every
    # organisation needs one — a development squad inside a club has no
    # recognised short form. A backfill that forced one would invent data.
    add_index :organisations, :acronym
  end
end
