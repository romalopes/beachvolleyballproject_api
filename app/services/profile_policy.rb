# Authorization boundary for PlayerProfile and CoachProfile operations.
# Authentication remains User/session based; profile ownership and permissions
# resolve through the user's Account. Legacy creator User IDs are honored only
# when the User has no Account mapping or the profile predates creator Accounts.
class ProfilePolicy
  def initialize(actor:, profile: nil)
    @actor = actor
    @account = actor.is_a?(Account) ? actor : actor&.account
    @user = actor.is_a?(User) ? actor : actor&.user
    @profile = profile
  end

  def create?
    admin? || coach?
  end

  def view?
    return false unless @profile && @actor
    return true if linked_account?(@profile)
    return true if admin? || curator?
    return @profile.visibility == "shared" if training_manager?

    false
  end

  def update?
    return false unless @profile
    return true if admin? || curator?
    return false unless coach?

    ProfileOwnership.created_by?(@profile, @actor) || linked_account?(@profile)
  end

  def invite?
    return false unless @profile
    return true if admin? || curator?

    coach? && ProfileOwnership.created_by?(@profile, @actor)
  end

  def review_claim?
    return false unless @profile
    return true if admin?

    coach? && ProfileOwnership.created_by?(@profile, @actor)
  end

  def unlink?
    admin? || curator?
  end

  def merge?
    admin? || curator?
  end

  def archive?
    admin? || curator?
  end

  def destroy?
    admin?
  end

  def self.scope(relation, actor:)
    policy = new(actor: actor)
    return relation.none unless actor
    return relation if policy.manager?

    policy.account ? relation.where(account_id: policy.account.id) : relation.none
  end

  def account = @account
  def manager? = admin? || curator? || coach?

  private

  attr_reader :account

  def linked_account?(profile)
    account && profile.account_id == account.id
  end

  def admin? = @account&.admin? || @user&.admin? || false
  def curator? = @account&.curator? || @user&.curator? || false
  def coach? = @account&.coach? || @user&.coach? || false
  def training_manager? = admin? || curator? || coach?
end
