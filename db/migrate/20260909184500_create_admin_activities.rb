class CreateAdminActivities < ActiveRecord::Migration[8.0]
  def change
    create_table :admin_activities do |t|
      t.bigint :user_id, null: false
      t.string :action, null: false
      t.string :entity_type, null: false
      t.bigint :entity_id, null: false
      t.string :entity_label
      t.string :ip_address
      t.string :user_agent
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
      t.index [:user_id]
      t.index [:entity_type, :entity_id]
      t.index [:action, :created_at]
    end
    add_foreign_key :admin_activities, :users
  end
end
