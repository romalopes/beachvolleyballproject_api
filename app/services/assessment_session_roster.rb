# Builds a draft assessment session's roster rows from permitted participant
# rows.
#
# The assessment form lets a coach add an existing player by profile id or
# create one inline through `person:`. The inline identity rules live in
# InlineParticipantResolver (D9/D10) and are invoked here — exactly as the
# training-session form invokes them — so the two flows cannot drift. Rows are
# persisted all-or-nothing: any rejected row rolls the whole batch back, so a
# failed request never leaves a half-built roster.
class AssessmentSessionRoster
  Result = Struct.new(:created, :failed, keyword_init: true)

  def initialize(session:, current_user:)
    @session = session
    @current_user = current_user
  end

  # Returns a Result with `created` (the persisted participants) and `failed`
  # (per-row validation errors). On any failure nothing is committed.
  def call(rows)
    created = []
    failed = []

    AssessmentSession.transaction do
      InlineParticipantResolver.new(created_by: current_user).call(rows)

      Array(rows).each do |row|
        participant = session.participants.build(
          player_profile_id: row[:player_profile_id],
          inclusion: row[:inclusion] || "included",
          missing_reason: row[:missing_reason]
        )

        if participant.save
          created << participant
        else
          failed << {
            player_profile_id: row[:player_profile_id],
            errors: participant.errors.full_messages
          }
        end
      end

      raise ActiveRecord::Rollback if failed.any?
    end

    Result.new(created: created, failed: failed)
  end

  private

  attr_reader :session, :current_user
end
