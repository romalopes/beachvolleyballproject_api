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

  # --- lifecycle authority (withdraw / restore / hard delete) -----------------

  # The creator of a record may always act on it, whatever its status. Sessions
  # are keyed on the coach of record and consolidations on `created_by_id`, so the
  # caller supplies the coach profile; everything else — curator, admin, another
  # coach, nobody signed in — is settled here.
  def record_creator?(record, coach_profile = nil)
    user = Current.user
    return false if user.nil?

    if record.is_a?(AssessmentSession) && coach_profile
      account_user = coach_account_user(coach_profile)
      return true if account_user.present? && account_user == user
    end

    record.respond_to?(:created_by_id) &&
      record.created_by_id.present? && record.created_by_id == user.id
  end

  def oversight?
    Current.user&.admin? || Current.user&.curator?
  end

  # Edit and delete while a record is a draft: its creator, a curator, or an admin.
  def authorize_draft_owner!(record, coach_profile = nil)
    return true if oversight? || record_creator?(record, coach_profile)

    render json: { error: "Forbidden" }, status: :forbidden
    false
  end

  # Withdrawing is a retraction of the author's own claim, so it carries the same
  # authority as editing — creator, curator, or admin — but only from `published`.
  def authorize_withdraw!(record, coach_profile = nil)
    return authorize_draft_owner!(record, coach_profile) if record.withdrawable?

    render json: { error: "Only published records can be withdrawn" },
           status: :unprocessable_entity
    false
  end

  # A withdrawn record has been retracted and is inert. Only an admin may bring it
  # back, edit it, or delete it — including its creator, who otherwise owns it. A
  # retraction its own author could quietly undo would not be a retraction.
  def authorize_admin_only!(record)
    return true if Current.user&.admin?

    render json: { error: "Only an admin can act on a withdrawn record" },
           status: :forbidden
    false
  end

  # Hard delete of a published record: the safety net for a mistaken publication,
  # so it is admin-only and deliberately narrower than every other rule here.
  def authorize_admin_delete!
    return true if Current.user&.admin?

    render json: { error: "Only an admin can delete a published record" },
           status: :forbidden
    false
  end
end
