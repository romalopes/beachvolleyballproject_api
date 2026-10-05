# Explains, in domain language, why a Person cannot be deleted.
#
# `Person` guards its associations with `dependent: :restrict_with_error`, which
# is the right rule — a profile carries the assessments, training participation
# and coaching periods that must not vanish with a row. But the raw Rails error
# ("Cannot delete record because dependent coach profiles exist") is unusable: it
# leaks a table name, it offers no action, and it reads like a fault rather than
# a deliberate protection.
#
# So the refusal is described in terms of what the caller knows — an account, a
# player profile, a coach profile — and, where one exists, what to do instead.
class PersonDeletionBlocker
  # Relation => [human label, what to do about it].
  RULES = {
    account: [
      "They are signed in as an account.",
      "Remove the account first if the person is no longer a user."
    ],
    player_profiles: [
      "They have a player profile.",
      "Archive the player profile instead of deleting it — it holds the training and assessment history."
    ],
    coach_profiles: [
      "They have a coach profile.",
      "Archive the coach profile instead of deleting it — it holds the coaching history."
    ],
    group_memberships: [
      "They belong to a squad.",
      "End the membership instead of deleting the person."
    ]
  }.freeze

  # Singular associations have no `.exists?`, so they are asked directly. Kept as
  # an explicit list rather than a `reflect_on_all_associations` sweep so the
  # wording for each relation stays deliberate and reviewable — and so a future
  # association cannot silently start blocking deletes with no explanation.
  SINGULAR = %i[account].freeze
  PLURAL = %i[player_profiles coach_profiles group_memberships].freeze

  def initialize(person)
    @person = person
  end

  # Empty when the person may be deleted.
  def messages
    blocking_relations.map { |relation| RULES.fetch(relation).first }
  end

  # The same reasons with their remedy, for a caller that can show them.
  def details
    blocking_relations.flat_map { |relation| RULES.fetch(relation) }
  end

  def blocked?
    blocking_relations.any?
  end

  private

  def blocking_relations
    @blocking_relations ||=
      SINGULAR.select { |relation| @person.public_send(relation).present? } +
      PLURAL.select { |relation| @person.public_send(relation).exists? }
  end
end
