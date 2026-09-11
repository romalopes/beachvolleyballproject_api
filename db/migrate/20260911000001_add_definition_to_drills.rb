class AddDefinitionToDrills < ActiveRecord::Migration[8.1]
  def change
    add_column :drills, :definition, :jsonb, null: false, default: {}
  end
end
