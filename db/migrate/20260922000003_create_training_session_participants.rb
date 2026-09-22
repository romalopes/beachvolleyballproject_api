# Phase 2: participants of a Training Session.
#
# Participation references the PlayerProfile (domain identity), never the
# User: an accountless player can be a participant and accumulate attendance
# history that survives later account creation and claiming.
class CreateTrainingSessionParticipants < ActiveRecord::Migration[8.1]
  def change
    create_table :training_session_participants do |t|
      t.references :training_session, null: false, foreign_key: true
      t.references :player_profile, null: false, foreign_key: true
      t.string :status, null: false, default: "invited"
      t.text :notes

      t.timestamps
    end

    add_index :training_session_participants, %i[training_session_id player_profile_id],
              name: "index_training_session_participants_on_session_and_player", unique: true
    add_index :training_session_participants, :status

    # Sessions are shared by default (visible to anyone browsing the
    # schedule). Private sessions are visible only to their participants and
    # to training managers — so a coach can schedule a training for a
    # specific player or group without publishing it to everyone.
    add_column :training_sessions, :visibility, string, null: false, default: "shared"
    add_index :training_sessions, :visibility
  end
end