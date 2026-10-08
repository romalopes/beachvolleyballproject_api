module Api
  module V1
    # Named sets of players a coach or club organizes to run sessions against.
    #
    # A group is a selection aid (plan §2 / D23): membership confers no
    # authorization or access of its own, so it carries no status or attendance.
    # Archive-not-delete: a group that has run assessment sessions cannot be
    # destroyed (preventing orphaned history); it must be archived instead.
    #
    # Read access is open to training managers (coach/curator/admin). Creation
    # and mutation requires a content creator (coach/admin). Private groups
    # observe soft visibility: hidden from other coaches unless administrator
    # or curator.
    class GroupsController < ApplicationController
      include ContentAuthorization
      include Pagination

      before_action :require_authentication
      before_action :require_training_manager!, except: :show
      before_action :require_content_creator!, only: %i[create update destroy add_members remove_member]
      before_action :set_group, only: %i[show update destroy add_members remove_member
                                         join approve_member reject_member]
      before_action :require_group_reader!, only: :show
      before_action :check_visibility!, only: %i[show update destroy add_members remove_member join]
      before_action :authorize_owner!, only: %i[update destroy add_members remove_member]

      def index
        groups = group_scope
                 .ordered
                 .includes(:created_by, :group_memberships)

        if params[:q].present?
          term = "%#{params[:q]}%"
          groups = groups.where("groups.name ILIKE :t OR groups.description ILIKE :t", t: term)
        end

        unless params[:include_private].present?
          groups = groups.visible_to(Current.user)
        end

        if params[:mine].present?
          groups = groups.owned_by(Current.user)
        end

        records, meta = paginate(groups)

        render json: {
          data: records.map { |g| serialize_summary(g) },
          groups: records.map { |g| serialize_summary(g) },
          meta: meta
        }
      end

      def show
        render json: {
          group: serialize_detail(@group)
        }
      end

      def create
        @group = Group.new(group_params)
        @group.created_by = Current.user

        # A group belongs to an organisation the caller is actually *in*. Being able
        # to name an organisation is not membership of it, and this is the one place
        # where the two are told apart.
        if @group.organisation_id.present? && !active_member_of?(@group.organisation_id)
          return render json: {
            errors: [ "You must be an active member of that organisation to create a group for it." ]
          }, status: :forbidden
        end

        if @group.save
          # The creator owns it, and ownership is a membership now (§2.6). Creating
          # the group without this row would produce a group nobody can manage —
          # exactly the state the old `created_by_id` check was papering over.
          if Current.user&.account
            @group.group_memberships.create!(
              account: Current.user.account,
              role: "owner",
              status: "active",
              joined_at: Time.current
            )
          end

          assign_account_ids(Array(params[:account_ids])) if params[:account_ids].present?

          render json: { group: serialize_detail(@group.reload) }, status: :created
        else
          render json: { errors: @group.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        # Re-pointing the group at an organisation needs the same standing as
        # choosing it in the first place: the model then checks the roster still
        # shares it.
        if params.dig(:group, :organisation_id).present? &&
           !active_member_of?(params.dig(:group, :organisation_id))
          return render json: {
            errors: [ "You must be an active member of that organisation to move this group to it." ]
          }, status: :forbidden
        end

        if params.key?(:account_ids)
          # Checked against the organisation this request *would* leave the group in,
          # and against the roster it *would* leave — a group being moved and
          # re-rostered together has to be judged as a whole, or the order of two
          # writes would decide whether the rule holds.
          proposed_accounts = params.key?(:account_ids) ? Array(params[:account_ids]).map(&:to_i) : @group.group_memberships.active.where.not(account_id: nil).pluck(:account_id)
          @group.group_memberships.owners.each do |membership|
            proposed_accounts << membership.account_id if membership.account_id
          end
          target_organisation = params.dig(:group, :organisation_id).presence ||
                                @group.organisation_id

          unless @group.shares_organisation?([], target_organisation,
                                             account_ids: proposed_accounts.uniq)
            return render json: {
              errors: [ "The roster must contain only active members of this group's organisation." ]
            }, status: :unprocessable_entity
          end
        end

        if @group.update(group_params)
          sync_account_ids(Array(params[:account_ids])) if params.key?(:account_ids)

          render json: { group: serialize_detail(@group.reload) }
        else
          render json: { errors: @group.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        if @group.assessment_sessions.exists?
          return render json: {
            errors: [ "Cannot delete group that has associated assessment sessions. Archive it instead." ]
          }, status: :unprocessable_entity
        end

        @group.destroy!
        render json: { message: "Group deleted successfully", id: @group.id }
      end

      # Add one or more accounts to the group's roster. Accounts may be unclaimed,
      # so a squad can still contain somebody without a login or profile.
      def add_members
        account_ids = Array(params[:account_ids] || params[:account_id]).compact.map(&:to_i)
        if account_ids.empty?
          return render json: { errors: [ "No roster members specified" ] }, status: :unprocessable_entity
        end

        # The rule that makes a group "members who share an Organisation" (§10): only
        # somebody actually in it can be added. 422 rather than 403 — the request
        # was well formed, the account simply does not belong.
        unless @group.shares_organisation?([], @group.organisation_id, account_ids: account_ids)
          return render json: {
            errors: [ "Each roster member must be an active member of this group's organisation." ]
          }, status: :unprocessable_entity
        end

        added = assign_account_ids(account_ids)

        render json: {
          group: serialize_detail(@group.reload),
          added: added
        }
      end

      # End a membership rather than removing the row (§2.5). The account stays on
      # the roster as history, which is what keeps a past assessment explicable.
      def remove_member
        account_id = params[:account_id].presence&.to_i || params[:person_id].presence&.to_i
        membership = @group.group_memberships.active.find_by(account_id: account_id)

        unless membership
          return render json: { errors: [ "That roster member is not active in this group" ] },
                        status: :not_found
        end

        # The one active owner is not walk-away-able: a group with no owner cannot
        # be managed by anybody, which is the failure §2.6 exists to prevent.
        if membership.owner?
          return render json: {
            errors: [ "The group's owner cannot be removed. Give the group another owner first." ]
          }, status: :unprocessable_entity
        end

        membership.end_membership!

        render json: {
          group: serialize_detail(@group.reload),
          removed: account_id
        }
      end

      # You add yourself. Distinct from `add_members`, which the group's owner does
      # to *somebody else* and which is owner-gated — joining writes your own row,
      # so it deliberately sits outside `authorize_owner!` rather than widening it.
      #
      # Role is fixed at `member`: self-granting `owner` or `coach` is precisely
      # the escalation this must not allow. The owner still assigns roles after.
      def join
        account = Current.user&.account
        if account.nil?
          return render json: {
            errors: [ "Your account is not ready to join a group." ]
          }, status: :unprocessable_entity
        end

        if @group.archived?
          return render json: {
            errors: [ "This group is archived and is not accepting members." ]
          }, status: :unprocessable_entity
        end

        # The §10 rule — a roster is members who share the group's organisation —
        # binds a self-service join exactly as it binds `add_members`. 422 rather
        # than 403: the request was well formed, the account simply is not in the club.
        if @group.organisation_id.present? &&
           !@group.shares_organisation?([], @group.organisation_id, account_ids: [ account.id ])
          return render json: {
            errors: [ "You must be an active member of this group's organisation to join it." ]
          }, status: :unprocessable_entity
        end

        existing = @group.group_memberships.find_by(account: account)

        # Already on the roster: 409 — well-formed request, conflicting state. A
        # `pending` row is recorded but not yet active, so it counts as already
        # having asked rather than as a reason to ask again.
        if existing && !existing.ended?
          return render json: {
            error: "You are already a member of this group.",
            membership: membership_payload(existing)
          }, status: :conflict
        end

        # Re-joining after leaving reactivates the same row rather than adding a
        # second one, so the earlier stint's history stays on the record — the same
        # rule `assign_account_ids` already follows (unique index across statuses).
        membership = existing || @group.group_memberships.build(account: account)
        membership.role = "member"
        membership.status = @group.approval_required? ? "pending" : "active"
        # A request that awaits approval has not joined yet: `joined_at` belongs to
        # the stint that is actually underway, and `activate!` stamps it on approval.
        membership.joined_at ||= Time.current if membership.status == "active"
        membership.left_at = nil

        if membership.save
          render json: { membership: membership_payload(membership) }, status: :created
        else
          render json: { errors: membership.errors.full_messages },
                 status: :unprocessable_entity
        end
      end

      # Approve a pending self-service join request. The group's owner plus
      # curator/admin oversight may approve — `Group#approvable_by?` is the single
      # source of that rule.
      def approve_member
        membership = find_membership
        return if performed?

        unless @group.approvable_by?(Current.user)
          return render json: {
            errors: [ "Only this group's owner, a curator or an admin can approve requests." ]
          }, status: :forbidden
        end

        unless membership.pending?
          return render json: { errors: [ "Only pending requests can be approved." ] }, status: :unprocessable_entity
        end

        # Re-checked at approval, not only at join: the club may have moved the
        # group or the requester's membership may have ended since the ask.
        if @group.organisation_id.present? &&
           !@group.shares_organisation?([], @group.organisation_id, account_ids: [ membership.account_id ])
          return render json: {
            errors: [ "That account is no longer an active member of this group's organisation." ]
          }, status: :unprocessable_entity
        end

        membership.activate!
        render json: { membership: membership_payload(membership) }
      end

      # Reject (withdraw) a pending self-service join request. The requester may
      # cancel their own request; approvers may reject it. A `pending` row records
      # no stint, so it is removed like any other unanswered request.
      def reject_member
        membership = find_membership
        return if performed?

        approver = @group.approvable_by?(Current.user)
        requester = membership.account_id == Current.user&.account&.id
        unless approver || requester
          return render json: { errors: [ "Only the requester or an approver can reject this request." ] }, status: :forbidden
        end

        unless membership.pending?
          return render json: { errors: [ "Only pending requests can be rejected." ] }, status: :unprocessable_entity
        end

        membership_id = membership.id
        membership.destroy!
        render json: { removed: true, membership_id: membership_id }
      end

      private

      # The pending/reviewable row addressed by `membership_id` in the URL. Scoped
      # to this group, so an id from another roster is a 404 rather than a way to
      # act on somebody else's membership.
      def find_membership
        membership = @group.group_memberships.find_by(id: params[:membership_id])
        return membership if membership

        render json: { errors: [ "That member is not on this group's roster" ] },
               status: :not_found
        nil
      end

      # One response shape for join/approve: the fields a client needs to render
      # the roster row it just created or changed, without the whole detail payload.
      def membership_payload(membership)
        {
          id: membership.id,
          group_id: membership.group_id,
          account_id: membership.account_id,
          name: membership.player_name,
          role: membership.role,
          status: membership.status,
          joined_at: membership.joined_at,
          left_at: membership.left_at
        }
      end

      def group_scope
        status = params[:status].presence
        if status == "all"
          Group.all
        elsif status.present?
          Group.where(status: status)
        else
          Group.active
        end
      end

      def set_group
        @group = Group.includes(:created_by, group_memberships: :account)
                      .find_by(id: params[:id]) ||
                 Group.includes(:created_by, group_memberships: :account)
                      .find_by!(slug: params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Group not found" }, status: :not_found
      end

      def check_visibility!
        return if @group.nil?
        return if @group.visible_to_user?(Current.user)

        render json: { error: "Group not found" }, status: :not_found
      end

      def require_group_reader!
        return if Current.user&.content_manager?
        return if @group&.group_memberships&.active&.exists?(account_id: Current.user&.account&.id)

        render json: { error: "Forbidden" }, status: :forbidden
      end

      def authorize_owner!
        return if @group.nil?
        return if Current.user&.admin? || @group.owner?(Current.user)

        render json: { error: "Forbidden" }, status: :forbidden
      end

      def group_params
        params.require(:group).permit(:name, :description, :visibility, :status,
                                      :organisation_id,
                                      # Join policy, same split as organisations: open
                                      # joins are immediate, approval-required ones
                                      # become a `pending` row the owner reviews.
                                      :requires_approval)
      end

      # Is this caller active in that organisation, either directly as the Account
      # or through one of their linked Player/Coach profiles?
      def active_member_of?(organisation_id)
        OrganisationMembership.where(
          organisation_id: organisation_id.to_i,
          status: "active"
        ).for_user_subjects(Current.user).exists?
      end

      # Adds accounts, re-activating an ended membership rather than adding a second
      # row for the same account: the unique index is on (group_id, account_id) across
      # all statuses, so a re-join that inserted would collide — and the first
      # stint's history has to stay on the record anyway (mirrors
      # organisation_memberships §4.4).
      def assign_account_ids(ids)
        added = 0
        Account.where(id: ids.map(&:to_i).uniq).find_each do |account|
          membership = @group.group_memberships.find_by(account_id: account.id)
          if membership.nil?
            @group.group_memberships.create!(account: account, joined_at: Time.current)
            added += 1
          elsif membership.ended?
            membership.update!(status: "active", left_at: nil)
            added += 1
          end
        end
        added
      end

      def sync_account_ids(ids)
        target_ids = ids.map(&:to_i).to_set
        @group.group_memberships.owners.each { |membership| target_ids << membership.account_id if membership.account_id }
        valid_ids = Account.where(id: target_ids.to_a).pluck(:id).to_set
        @group.group_memberships.active.where.not(account_id: nil).where.not(account_id: valid_ids.to_a)
              .find_each { |membership| membership.end_membership! }
        assign_account_ids(valid_ids.to_a)
      end

      def serialize_summary(group)
        group.metadata
      end

      def serialize_detail(group)
        members = group.group_memberships.sort_by(&:id).map do |membership|
          account = membership.account
          # The player profile is optional now: a squad may hold somebody who never
          # registered as a player (§2.2), so these three are legitimately nil.
          player = account&.player_profiles&.first
          {
            id: membership.id,
            account_id: membership.account_id,
            name: account&.full_name,
            player_profile_id: player&.id,
            level: player&.level,
            preferred_position: player&.preferred_position,
            email: account&.email,
            role: membership.role,
            status: membership.status,
            joined_at: membership.joined_at,
            left_at: membership.left_at
          }
        end

        # `players` kept as an alias of `members` for now: it is the same list, and
        # dropping it in the same change as the key rename would break callers for
        # no gain. It goes when the SPA is moved over.
        group.metadata.merge(
          members: members,
          players: members
        )
      end
    end
  end
end
