module ContentAuthorization
  extend ActiveSupport::Concern

  private

  # Coaches and admins may create content.
  def require_content_creator!
    return if Current.user&.coach? || Current.user&.admin?

    render_unauthorized_or_forbidden
  end

  # Profile writes use Account-aware policy checks. User roles continue to
  # decide whether an authenticated principal may create the domain record.
  def require_profile_creator!
    return if ProfilePolicy.new(actor: Current.user).create?

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
    coach_profile&.account&.user
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

  # --- organisation authority -------------------------------------------------
  #
  # Reading an organisation is open to any training manager, because the tree is
  # context everyone shares. *Editing* one is delegated: a club's name and logo are
  # its own to correct, so the club's officers, its current creator, curators and
  # admins may all change them, rather than the site admin alone.
  #
  # Creating and re-parenting stay admin-only. Both assert something *about other
  # organisations* — a new node's place in the federation tree is a claim made to
  # every other club — and that is a site-level judgement rather than a club's own.
  def require_organisation_admin!
    return true if Current.user&.admin?

    render json: { error: "Only an admin can create or re-parent organisations" },
           status: :forbidden
    false
  end

  # Editing an existing organisation: its own record, as opposed to its position in
  # the tree. Split from `require_organisation_admin!` for the reason above.
  #
  # The creator's grant is time-limited inside `Organisation#editable_by?` — it
  # lapses when they leave — so a resigned founder cannot keep renaming the club.
  def require_organisation_editor!
    return true if OrganisationAccess.can_edit?(@organisation, Current.user)

    render json: {
      error: "Only this organisation's officers, its creator, a curator or an admin can edit it"
    }, status: :forbidden
    false
  end

  # Hard delete. Narrower than every other organisation rule, because it is the one
  # action that destroys the record rather than changing it.
  def authorize_organisation_delete!
    return true if Current.user&.admin?

    render json: { error: "Only an admin can delete an organisation" },
           status: :forbidden
    false
  end

  # Changing who belongs to an organisation: its owner and its administrators, plus
  # a site admin. Split out from `require_organisation_admin!` because membership is
  # a *delegated* authority — a club's own officers run their roster — whereas
  # creating and re-parenting the organisation itself is a site-level claim.
  #
  # An ordinary member is refused even though they can already see the roster: being
  # on it is not authority over it.
  def require_organisation_membership_manager!
    return true if OrganisationAccess.can_manage_members?(@organisation, Current.user)

    render json: {
      error: "Only this organisation's owner or administrators can manage its members"
    }, status: :forbidden
    false
  end

  # Site administration, for the few actions that are neither content creation nor
  # delegated to a club's own officers: deleting a person, and promoting somebody to
  # a player or a coach. Curators are oversight, not administration, and are refused.
  def require_admin!
    return true if Current.user&.admin?

    render json: { error: "Only an admin can do this" }, status: :forbidden
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
