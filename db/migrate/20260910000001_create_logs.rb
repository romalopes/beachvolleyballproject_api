class CreateLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :logs do |t|
      t.string :description, null: false
      t.bigint :user_id
      t.string :action, null: false
      t.string :method, null: false
      t.string :path
      t.string :ip_address
      t.text :user_agent
      t.string :request_id
      t.integer :status

      t.timestamps
    end

    add_index :logs, :user_id
    add_index :logs, :request_id
    add_index :logs, :created_at
    add_index :logs, [:action, :created_at]
    add_index :logs, [:user_id, :created_at]
  end
end
