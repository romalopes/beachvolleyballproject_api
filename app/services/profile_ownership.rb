# Central ownership rules for PlayerProfile and CoachProfile.
#
# `created_by_id` remains the compatibility attribution to User. New records
# also carry `created_by_account_id`, the stable domain owner used by identity
# operations. Account provisioning is lazy in this application, so recording a
# profile creates the creator's Account/Person in the same transaction.
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
    if account && profile.respond_to?(:created_by_account_id) && profile.created_by_account_id == account.id
      return true
    end

    user = user_or_account.is_a?(User) ? user_or_account : user_or_account.user
    user && profile.respond_to?(:created_by_id) && profile.created_by_id == user.id
  end

  def self.account_scope(relation, user)
    return relation.none unless user

    legacy = relation.where(created_by_id: user.id)
    account_id = user.account&.id
    account_id ? legacy.or(relation.where(created_by_account_id: account_id)) : legacy
  end
end
