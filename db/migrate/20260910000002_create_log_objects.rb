class CreateLogObjects < ActiveRecord::Migration[8.0]
  def change
    create_table :log_objects do |t|
      t.references :log, null: false, foreign_key: true
      t.references :object, polymorphic: true, null: false

      t.timestamps
    end

    add_index :log_objects, [:object_type, :object_id]
  end
end
