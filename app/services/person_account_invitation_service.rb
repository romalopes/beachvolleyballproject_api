# Legacy email invitation that transfers eligible profile and roster links to
# an Account. Account contact details are copied once and are no longer synced
# with the historical roster identity.
class PersonAccountInvitationService
  class InvitationError < StandardError; end

  INVALID_MESSAGE = "This account invitation is invalid, expired, revoked, used, or not eligible for this account.".freeze
  VERIFICATION_MESSAGE = "Verify this account's email address before accepting the invitation.".freeze

  def self.issue!(person:, invited_by:)
    raise InvitationError, INVALID_MESSAGE unless eligible_person?(person)

    raw_token = SecureRandom.urlsafe_base64(32)
    invitation = PersonAccountInvitation.transaction do
      person.with_lock do
        raise InvitationError, INVALID_MESSAGE unless eligible_person?(person)

        now = Time.current
        person.person_account_invitations.active.each do |prior|
          prior.update!(status: prior.expires_at <= now ? "expired" : "revoked",
                        revoked_at: prior.expires_at <= now ? nil : now)
        end
        person.person_account_invitations.create!(
          invited_by: invited_by,
          invitee_email: person.email,
          token_digest: digest(raw_token),
          expires_at: now + PersonAccountInvitation::DEFAULT_EXPIRATION,
          status: "active"
        )
      end
    end
    [ invitation, raw_token ]
  end

  def self.redeem!(raw_token:, user:)
    invitation = PersonAccountInvitation.find_by(token_digest: digest(raw_token.to_s))
    raise InvitationError, INVALID_MESSAGE unless invitation
    person = Person.find_by(id: invitation.person_id)
    raise InvitationError, INVALID_MESSAGE unless person

    PersonAccountInvitation.transaction do
      person.with_lock do
        invitation.with_lock do
          user.with_lock do
            raise InvitationError, INVALID_MESSAGE unless invitation.status == "active" && invitation.expires_at > Time.current
            raise InvitationError, INVALID_MESSAGE unless eligible_person?(person)
            raise InvitationError, INVALID_MESSAGE unless user.email_address.to_s.strip.downcase == invitation.invitee_email
            raise InvitationError, VERIFICATION_MESSAGE unless user.email_verified?

            account = user.account || Account.new(user: user)
            unless account.persisted?
              account.build_contact_detail(first_name: person.first_name, last_name: person.last_name,
                email: person.email, phone: person.phone, date_of_birth: person.date_of_birth)
              account.save!
            end
            link_person_records!(person, account)
            invitation.update!(status: "used", used_by: user, used_at: Time.current)
          end
        end
      end
    end
    invitation
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    raise InvitationError, INVALID_MESSAGE
  end

  def self.revoke!(invitation:)
    PersonAccountInvitation.transaction do
      invitation.person.with_lock do
        invitation.with_lock do
          raise InvitationError, INVALID_MESSAGE unless invitation.status == "active"
          if invitation.expires_at <= Time.current
            invitation.update!(status: "expired")
          else
            invitation.update!(status: "revoked", revoked_at: Time.current)
          end
        end
      end
    end
    invitation
  end

  def self.eligible_person?(person)
    person&.status == "active" && person.email.present? &&
      URI::MailTo::EMAIL_REGEXP.match?(person.email.to_s.strip) &&
      (person.player_profiles.exists? || person.coach_profiles.exists?) && linked_accounts(person).empty?
  end
  private_class_method :eligible_person?

  def self.linked_accounts(person)
    account_ids = person.player_profiles.where.not(account_id: nil).pluck(:account_id) +
      person.coach_profiles.where.not(account_id: nil).pluck(:account_id)
    Account.where(id: account_ids.uniq)
  end
  private_class_method :linked_accounts

  def self.link_person_records!(person, account)
    now = Time.current
    person.player_profiles.where(account_id: nil).update_all(account_id: account.id, updated_at: now)
    person.coach_profiles.where(account_id: nil).update_all(account_id: account.id, updated_at: now)
    person.organisation_memberships.where(account_id: nil).update_all(account_id: account.id, updated_at: now)
    person.group_memberships.where(account_id: nil).update_all(account_id: account.id, updated_at: now)
  end
  private_class_method :link_person_records!

  def self.digest(raw_token)
    Digest::SHA256.hexdigest(raw_token)
  end
  private_class_method :digest
end
