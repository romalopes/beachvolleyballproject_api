# Single creation path for people recorded by staff.
#
# A coach (or admin) can enter a player or coach who does not have an account
# yet. Those people must be distinguishable from self-signups — identity
# resolution, invitations and consolidation all branch on `creation_source` —
# so the provenance rules live here instead of being copied into every
# controller that records a person:
#
#   * `creation_source` is always "coach_created" (not a self-signup);
#   * `created_by` records the staff user who entered the person (audit);
#   * `status` defaults to "active".
#
# Used by Api::V1::PlayersController / CoachesController (nested
# `person_attributes`) and by the training-session inline participant flow
# (`TrainingSessionsController#resolve_inline_participants!`).
class PersonCreationService
  CREATION_SOURCE = "coach_created".freeze

  def initialize(created_by:)
    @created_by = created_by
  end

  # Stamps the staff-creation defaults onto an unsaved Person and returns it.
  # Safe to call with nil (returns nil) so callers can use `profile.person`
  # without a guard.
  def apply(person)
    return person if person.nil?

    person.created_by ||= @created_by
    person.creation_source = CREATION_SOURCE
    person.status = "active" if person.status.blank?
    person
  end

  # Builds an unsaved Person carrying the staff-creation defaults. The person
  # is NOT saved: callers attach a profile first and persist both together.
  def build(person_attributes = {})
    apply(Person.new(person_attributes.to_h))
  end
end
