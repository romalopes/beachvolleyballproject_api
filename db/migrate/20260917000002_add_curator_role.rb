# Curators share content-management permissions with coaches and admins
# (including Training Sessions), so the role must exist to be assignable.
class AddCuratorRole < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      INSERT INTO roles (name, created_at, updated_at)
      VALUES ('curator', NOW(), NOW())
      ON CONFLICT (name) DO NOTHING
    SQL
  end

  def down
    execute "DELETE FROM roles WHERE name = 'curator'"
  end
end
