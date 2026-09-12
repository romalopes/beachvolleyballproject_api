class AddImpersonatedUserToSessions < ActiveRecord::Migration[8.1]
  def change
    # Nullable: set only on sessions where an admin is impersonating a user.
    add_reference :sessions, :impersonated_user, null: true, foreign_key: { to_table: :users }
  end
end
