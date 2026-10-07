# Creates a draft AssessmentSession and, when one is named, seeds its roster
# from that group — as one unit.
#
# The atomicity is the point. Seeding after a successful save would leave a
# half-built draft behind whenever any membership failed: a session with a name
# and a date but an empty roster, which a coach cannot tell apart from one they
# forgot to fill in. Saving and seeding share a transaction so the roster is
# either fully seeded or the session does not exist.
#
# `seeder` is injectable so the rollback is directly testable. Minitest 6
# dropped `minitest/mock`, and more importantly a test that only ever exercises
# the success path is exactly what let the original bug through.
class AssessmentSessionCreator
  def initialize(session:, seeder: nil)
    @session = session
    @seeder = seeder || method(:seed_roster_from_group)
  end

  # Returns the persisted session, or the unsaved one carrying its validation
  # errors when the model refused it. Raises whatever the seeder raised, having
  # rolled the transaction back.
  def call
    AssessmentSession.transaction do
      if @session.save
        @seeder.call(@session)
      else
        raise ActiveRecord::Rollback
      end
    end

    @session
  end

  private

  # A group is a selection aid: its members start the roster as `included`, and
  # the coach still removes anyone who did not turn up (membership is not
  # attendance). Players already on the roster are skipped rather than raising,
  # so an overlapping group cannot block creation.
  #
  # Roster membership is a Person and the roster rows are still PlayerProfile-keyed,
  # so a member with no player profile has nothing to seed. They are skipped rather
  # than created on the fly: a Participant row is a coach's record of a person
  # assessed, and inventing a player profile to satisfy a roster would fabricate
  # exactly that. Only *active* memberships seed — somebody who left the squad is
  # not somebody being assessed.
  def seed_roster_from_group(session_record)
    return if session_record.group.nil?

    existing = session_record.participants.map(&:player_profile_id).to_set
    session_record.group.group_memberships.active.includes(account: :player_profiles).each do |membership|
      profile = membership.account.player_profiles.first
      next if profile.nil?
      next if existing.include?(profile.id)

      session_record.participants.create!(player_profile: profile, inclusion: "included")
    end
  end
end
