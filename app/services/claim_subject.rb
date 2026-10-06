# Eligibility and Account-linking behavior for a profile or a legacy Person
# invitation that predates the profile-only claim workflow.
class ClaimSubject
  class Ineligible < StandardError; end

  attr_reader :record

  def initialize(record)
    @record = record
  end

  def self.for(record)
    return new(record) if record.is_a?(PlayerProfile) || record.is_a?(CoachProfile) || record.is_a?(Person)

    raise Ineligible, "Only recorded profiles or legacy Person invitations can be claimed."
  end

  def kind = record.class.name
  def label = record.is_a?(PlayerProfile) ? "player profile" : (record.is_a?(CoachProfile) ? "coach profile" : "recorded identity")

  def eligible?
    return eligible_person? if record.is_a?(Person)

    record.status == "active" && record.account_id.nil? && record.full_name.present?
  end

  def ineligibility_reason
    "The profile must be active, named, and not already linked to an account."
  end

  def default_email
    record.is_a?(Person) ? record.email : nil
  end

  def still_unclaimed?
    return eligible_person? if record.is_a?(Person)

    record.account_id.nil?
  end

  def effect!(claimant_account:, **_unused)
    return link_person_records!(claimant_account) if record.is_a?(Person)

    record.update!(account: claimant_account)
    record
  end

  private

  def eligible_person?
    record.status == "active" && record.email.present? &&
      (record.player_profiles.exists? || record.coach_profiles.exists?) &&
      linked_accounts.empty?
  end

  def linked_accounts
    ids = record.player_profiles.where.not(account_id: nil).pluck(:account_id) +
      record.coach_profiles.where.not(account_id: nil).pluck(:account_id)
    Account.where(id: ids.uniq)
  end

  def link_person_records!(account)
    now = Time.current
    record.player_profiles.where(account_id: nil).update_all(account_id: account.id, updated_at: now)
    record.coach_profiles.where(account_id: nil).update_all(account_id: account.id, updated_at: now)
    record.organisation_memberships.where(account_id: nil).update_all(account_id: account.id, updated_at: now)
    record.group_memberships.where(account_id: nil).update_all(account_id: account.id, updated_at: now)
    record
  end
end
