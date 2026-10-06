# Central ownership rules for PlayerProfile and CoachProfile.
#
# `created_by_id` remains a legacy attribution to User. Application ownership
# resolves through Account, which is distinct from the profile's creator.
class ProfileOwnership
  def self.account_for(user)
    user.with_lock do
      user.account || user.create_account!
    end
  end

  def self.stamp!(profile, user)
    account = account_for(user)
    profile.created_by ||= user
    profile.created_by_account ||= account
    profile
  end

  def self.owned_by?(profile, user_or_account)
    return false unless profile && user_or_account

    account = user_or_account.is_a?(Account) ? user_or_account : user_or_account.account
    return true if account && [profile.account_id, profile.created_by_account_id].compact.include?(account.id)

    user = user_or_account.is_a?(User) ? user_or_account : user_or_account.user
    user && profile.created_by_id == user.id
  end

  def self.created_by?(profile, user_or_account)
    return false unless profile && user_or_account

    account = user_or_account.is_a?(Account) ? user_or_account : user_or_account.account
    return true if account && profile.created_by_account_id == account.id

    user = user_or_account.is_a?(User) ? user_or_account : user_or_account.user
    user && profile.created_by_id == user.id
  end

  def self.account_scope(relation, user)
    return relation.none unless user

    account_id = user.is_a?(Account) ? user.id : user.account&.id
    legacy_user_id = user.is_a?(User) ? user.id : user.user_id
    if account_id
      relation.where(account_id: account_id)
      .or(relation.where(created_by_account_id: account_id))
      .or(relation.where(created_by_id: legacy_user_id))
    else
      relation.where(created_by_id: legacy_user_id)
    end
  end

  def self.linked_to?(profile, user_or_account)
    return false unless profile && user_or_account

    account = user_or_account.is_a?(Account) ? user_or_account : user_or_account.account
    account && profile.account_id == account.id
  end
end
