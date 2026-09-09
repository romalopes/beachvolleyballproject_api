class AddApiTokenToSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :sessions, :api_token, :string
    add_column :sessions, :api_token_expires_at, :datetime
    add_index :sessions, :api_token, unique: true
  end
end