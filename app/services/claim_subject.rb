# Eligibility and effect for one kind of invitation subject.
#
# The point of the polymorphic `claim_invitations` table is that "who may be
# invited" and "what accepting does" differ per subject. Keeping those two
# questions together per subject stops the difference from leaking into the
# service, the controller and the UI as parallel code paths.
class ClaimSubject
  class Ineligible < StandardError; end

  attr_reader :record

  def initialize(record)
    @record = record
  end

  # Returns a new instance of the right class for `record`, or raises when the
  # record is not a recognised subject.
  def self.for(record)
    case record
    when PlayerProfile then new(record)
    when CoachProfile  then new(record)
    when Person        then new(record)
    else raise Ineligible, "That record cannot be the subject of a claim invitation."
    end
  end

  def kind = record.class.name

  # Human label used in review queues and audit text.
  def label
    case record
    when PlayerProfile then "player profile"
    when CoachProfile  then "coach profile"
    else "person"
    end
  end

  # Can the club issue an invitation for this subject right now?
  def eligible?
    case record
    when PlayerProfile then record.person_id.nil? && record.status == "active" && record.display_name.present?
    when CoachProfile  then record.person_id.nil? && record.status == "active"
    else person_eligible?
    end
  end

  # Why not. Kept specific so the coach is told what to fix.
  def ineligibility_reason
    case record
    when PlayerProfile then "The player profile must be active, unlinked, and have a display name."
    when CoachProfile  then "The coach profile must be active and unlinked to a Person."
    else "The person must be active, have no account yet, and have a valid email address."
    end
  end

  # The address an invitation is restricted to, when the subject has one.
  # A Person always does; a profile only when the club supplies one.
  def default_email
    record.is_a?(Person) ? record.email : nil
  end

  # Does this subject still need a claim, i.e. is the thing being attached
  # absent? Re-checked at redemption so a subject claimed meanwhile is refused.
  def still_unclaimed?
    record.is_a?(Person) ? record.account.nil? : record.person_id.nil?
  end

  # Apply an approved claim: return the Person the subject should end up on, and
  # any Person that should be retired. `person:` is the identity asserting the
  # claim; for a Person subject it is the claim itself.
  def effect!(claimant_person:, actor:)
    case record
    when PlayerProfile, CoachProfile
      record.update!(person: claimant_person)
      nil
    else
      attach_account!(claimant_person: claimant_person, actor: actor)
    end
  end

  private

  def person_eligible?
    record.status == "active" && record.account.nil? && record.email.present? &&
      URI::MailTo::EMAIL_REGEXP.match?(record.email.to_s.strip)
  end

  # Moves the claimant's login onto this Person and retires the disposable
  # signup Person it was pointing at.
  #
  # Order matters: the placeholder was loaded through `account.person`, so once
  # the Account is re-pointed that object is stale and saving it afterwards
  # writes the old `person_id` back. Retiring first never touches the inverse.
  def attach_account!(claimant_person:, actor:)
    account = claimant_person.account
    unless account
      raise Ineligible, "This person has no account to connect."
    end

    placeholder = account.person
    unless placeholder && placeholder.id != record.id
      Account.create!(user: account.user, person: record)
      return nil
    end

    unless disposable_signup_placeholder?(placeholder, account)
      raise Ineligible, "This account already has an identity that cannot be replaced automatically."
    end

    placeholder.update!(status: "merged", merged_into: record, merged_by: actor)
    account.update!(person: record)
    placeholder
  end

  # Signup builds an empty Person for backwards compatibility. Only that stub
  # may move; any identity carrying profile or membership history is a real
  # conflict and must go through staff review instead.
  def disposable_signup_placeholder?(placeholder, account)
    placeholder.status == "active" && placeholder.creation_source == "signup" &&
      placeholder.created_by_id == account.user_id && placeholder.player_profiles.empty? &&
      placeholder.coach_profiles.empty? && placeholder.group_memberships.empty? &&
      placeholder.organisation_memberships.empty? && placeholder.merged_from.empty?
  end
end
