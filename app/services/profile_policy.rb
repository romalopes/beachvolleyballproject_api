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
    return true if coach? && ProfileOwnership.created_by?(@profile, @actor)
    return true if @profile.visibility == "shared" && training_manager?
    return true if player_peer_access?

    false
  end

  def update?
    return false unless @profile
    return true if admin?
    coach? && view?
  end

  def can_view_collection?
    manager? || @account.present?
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
    update?
  end

  def destroy?
    admin?
  end

  def self.scope(relation, actor:)
    policy = new(actor: actor)
    return relation.none unless actor
    return relation if policy.manager?

    scoped = if policy.account
      relation.where(account_id: policy.account.id)
    elsif actor.is_a?(User)
      relation.where(created_by_id: actor.id)
    else
      relation.none
    end
    scoped
  end

  def account = @account
  def manager? = admin? || curator? || coach?

  private

  def linked_account?(profile)
    ProfileOwnership.linked_to?(profile, @actor)
  end

  def player_peer_access?
    return false unless @profile.is_a?(PlayerProfile) && training_manager? && @account

    organisation_ids = OrganisationMembership.active.where(account_id: @account.id).pluck(:organisation_id)
    return false if organisation_ids.empty?

    peer_account_ids = OrganisationMembership.active.where(organisation_id: organisation_ids).where.not(account_id: nil).pluck(:account_id)
    peer_account_ids.include?(@profile.account_id)
  end

  def admin? = @account&.admin? || @user&.admin? || false
  def curator? = @account&.curator? || @user&.curator? || false
  def coach? = @account&.coach? || @user&.coach? || false
  def training_manager? = admin? || curator? || coach?
end
