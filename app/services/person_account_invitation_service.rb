# Issues and accepts invitations that attach a login Account to an existing
# Person. Matching a verified email address is the proof of ownership; the
# existing profiles and their history stay on that Person throughout.
class PersonAccountInvitationService
  class InvitationError < StandardError; end

  INVALID_MESSAGE = "This account invitation is invalid, expired, revoked, used, or not eligible for this account.".freeze
  VERIFICATION_MESSAGE = "Verify this account's email address before accepting the invitation.".freeze

  def self.issue!(person:, invited_by:)
    raise InvitationError, "An active Person with an email address and no Account is required." unless eligible_person?(person)

    raw_token = SecureRandom.urlsafe_base64(32)
    invitation = PersonAccountInvitation.transaction do
      person.with_lock do
        raise InvitationError, "An active Person with an email address and no Account is required." unless eligible_person?(person)

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
      # Keep the same lock order as issue!: Person, then invitation. The User row
      # serializes two invitations racing to attach an Account to one login.
      person.with_lock do
        invitation.with_lock do
          user.with_lock do
            raise InvitationError, INVALID_MESSAGE unless invitation.status == "active"
            raise InvitationError, INVALID_MESSAGE if invitation.expires_at <= Time.current || !eligible_person?(person)
            unless user.email_address.to_s.strip.downcase == invitation.invitee_email
              raise InvitationError, INVALID_MESSAGE
            end
            raise InvitationError, VERIFICATION_MESSAGE unless user.email_verified?
            account = user.account
            if account
              placeholder = account.person
              unless signup_placeholder?(placeholder, user)
                raise InvitationError, INVALID_MESSAGE
              end

              # Order matters. `placeholder` was loaded through `account.person`,
              # so once the account is re-pointed it is a stale object whose cached
              # `has_one :account` inverse still points at this row; saving it
              # afterwards writes that stale association back and silently undoes
              # the move. Retiring the placeholder first never touches the
              # account's inverse, so the re-point is what survives.
              if placeholder && placeholder.id != person.id
                placeholder.update!(status: "merged", merged_into: person,
                                    merged_by: invitation.invited_by)
              end
              account.update!(person: person)
            else
              Account.create!(user: user, person: person)
            end
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

  def self.digest(raw_token)
    Digest::SHA256.hexdigest(raw_token)
  end
  private_class_method :digest

  def self.eligible_person?(person)
    person&.status == "active" && person.account.nil? &&
      person.email.present? && URI::MailTo::EMAIL_REGEXP.match?(person.email.to_s.strip)
  end
  private_class_method :eligible_person?

  # Signup creates an empty Person immediately for compatibility with older
  # account flows. Permit only that disposable stub to move; any identity with
  # profile or membership history remains a hard conflict requiring review.
  def self.signup_placeholder?(person, user)
    person&.status == "active" && person.creation_source == "signup" &&
      person.created_by_id == user.id && person.player_profiles.empty? &&
      person.coach_profiles.empty? && person.group_memberships.empty? &&
      person.organisation_memberships.empty? && person.merged_from.empty?
  end
  private_class_method :signup_placeholder?
end
