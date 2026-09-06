class CreateTrainingSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :training_sessions do |t|
      t.references :drill, null: false, foreign_key: true
      t.datetime :scheduled_at
      t.string :location
      t.text :notes

      t.timestamps
    end
  end
end
