class CreateAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :accounts do |t|
      t.belongs_to :user, null: false, foreign_key: true, index: { unique: true }
      t.string :first_name
      t.string :last_name
      t.string :phone
      t.date :date_of_birth

      t.timestamps
    end
  end
end