# Eligibility and Account-linking behavior for a recorded profile.
class ClaimSubject
  class Ineligible < StandardError; end

  attr_reader :record

  def initialize(record)
    @record = record
  end

  def self.for(record)
    return new(record) if record.is_a?(PlayerProfile) || record.is_a?(CoachProfile)

    raise Ineligible, "Only recorded player and coach profiles can be claimed."
  end

  def kind = record.class.name
  def label = record.is_a?(PlayerProfile) ? "player profile" : "coach profile"

  def eligible?
    record.status == "active" && record.account_id.nil? && record.full_name.present?
  end

  def ineligibility_reason
    "The profile must be active, named, and not already linked to an account."
  end

  def default_email
    nil
  end

  def still_unclaimed?
    record.account_id.nil?
  end

  def effect!(claimant_account:, **_unused)
    record.update!(account: claimant_account)
    record
  end
end
