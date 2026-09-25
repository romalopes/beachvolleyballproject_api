# One PlayerProfile's membership of a Group.
#
# This is the join between a roster and the domain identity, so a player without
# an account can be grouped — the same reasoning as TrainingSessionParticipant.
#
# There is deliberately no status column: membership means "this player is in
# this squad". Anything more transient (invited / confirmed / attended / absent)
# belongs to the session that observed it, where it is evidence, not to the
# roster, where it would be a stale opinion.
class GroupMembership < ApplicationRecord
  belongs_to :group, inverse_of: :group_memberships
  belongs_to :player_profile, inverse_of: :group_memberships

  has_one :person, through: :player_profile

  validates :player_profile_id, uniqueness: { scope: :group_id }

  scope :ordered, -> { order(:id) }

  def player_name
    person&.full_name
  end
end
