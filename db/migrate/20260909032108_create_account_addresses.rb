class CreateAccountAddresses < ActiveRecord::Migration[8.1]
  def change
    create_table :account_addresses do |t|
      t.belongs_to :account, null: false, foreign_key: true, index: { unique: true }
      t.string :street_address
      t.string :city
      t.string :state
      t.string :postal_code
      t.string :country

      t.timestamps
    end
  end
end