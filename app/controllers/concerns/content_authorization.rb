module ContentAuthorization
  extend ActiveSupport::Concern

  private

  # Coaches and admins may create content.
  def require_content_creator!
    return if Current.user&.coach? || Current.user&.admin?

    render_unauthorized_or_forbidden
  end

  # Trainings are shared resources managed by coaches, curators and admins.
  # This is deliberately NOT keyed off `training_session.created_by_id`: a
  # session created yesterday by one coach must stay manageable by the other
  # coaches, curators and admins responsible for the shared schedule.
  def require_training_manager!
    return if Current.user&.content_manager?

    render_unauthorized_or_forbidden
  end

  # Owners and admins may modify/delete content.
  def authorize_content_owner!(owner)
    return if Current.user&.admin? || Current.user == owner

    render_unauthorized_or_forbidden
  end

  # The User behind a domain coach profile, when that coach has an account.
  # A coach recorded without an account has no User to match against, so this
  # is nil and the caller treats that as "not the coach of record".
  def coach_account_user(coach_profile)
    coach_profile&.person&.account&.user
  end

  # Session authority (assessment plan §4): oversight (curator/admin) OR the
  # coach of record for the supplied profile. Content management alone is
  # deliberately NOT enough — a manager who is not the coach of record cannot
  # rewrite someone else's professional ratings. Both session controllers
  # include this concern, so the rule lives in one place for each of them.
  def oversight_or_coach_of_record?(coach_profile, user = Current.user)
    return true if user&.admin? || user&.curator?

    account_user = coach_account_user(coach_profile)
    account_user.present? && account_user == user
  end
end
