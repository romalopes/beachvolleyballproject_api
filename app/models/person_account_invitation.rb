# Single-use invitation for linking a login Account to an existing, accountless
# Person. It is distinct from PlayerClaimInvitation, which attaches an unlinked
# PlayerProfile to a Person.
class PersonAccountInvitation < ApplicationRecord
  STATUSES = %w[active used revoked expired].freeze
  DEFAULT_EXPIRATION = 7.days

  belongs_to :person
  belongs_to :invited_by, class_name: "User"
  belongs_to :used_by, class_name: "User", optional: true

  normalizes :invitee_email, with: ->(value) { value.to_s.strip.downcase }

  validates :invitee_email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :token_digest, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :expires_at, presence: true
  validates :used_at, presence: true, if: -> { status == "used" }
  validates :used_by, presence: true, if: -> { status == "used" }
  validates :revoked_at, presence: true, if: -> { status == "revoked" }

  scope :active, -> { where(status: "active") }

  def effective_status(now: Time.current)
    status == "active" && expires_at <= now ? "expired" : status
  end

  def summary
    {
      id: id,
      person_id: person_id,
      invitee_email: invitee_email,
      status: effective_status,
      expires_at: expires_at,
      used_at: used_at,
      revoked_at: revoked_at,
      created_at: created_at
    }
  end
end
