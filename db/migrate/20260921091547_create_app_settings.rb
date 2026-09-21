# Singleton-style global configuration storage: one row per setting key.
# Values are stored as strings; AppSetting coerces them to their typed values
# (currently booleans and strings). This lets admins toggle runtime settings
# (e.g. "save logs to database", "test mode") via the Configuration page
# instead of redeploying. Mirrors the pattern in the wine words project.
class CreateAppSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :app_settings do |t|
      t.string :key, null: false
      t.text :value
      t.timestamps
    end
    add_index :app_settings, :key, unique: true
  end
end