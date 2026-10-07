module Api
  module V1
    # A hierarchical organisational context — an international federation, a
    # national body, a state association, a club, an academy.
    #
    # One self-referencing table, never a table per level: the depth is
    # unbounded, so nothing here may assume how many tiers exist and no code may
    # branch on `organisation_type` to decide behaviour.
    #
    # Read is gated the same way as the other people-facing catalogues (groups,
    # players, coaches): a training manager, not any signed-in account. Opening
    # the tree to player accounts would make this the only roster in the app they
    # can read, which is not what "shared context" should mean here.
    class OrganisationsController < ApplicationController
      include ContentAuthorization
      include Pagination

      before_action :require_authentication
      before_action :require_training_manager!, except: :show
      # Loaded before the authority checks, not after: every organisation rule below
      # needs the record it is judging, and a rule that silently passed because the
      # record was nil would be the worst kind of bug here.
      before_action :set_organisation,
                    only: %i[show update archive restore logo destroy
                             members member_candidates create_member update_member end_member join]
      before_action :require_organisation_reader!, only: :show
      # Creating a node and moving one are claims made *to other clubs* about the
      # tree, so they stay admin-only.
      before_action :require_organisation_admin!, only: %i[create]
      # Editing the record is the club's own business.
      before_action :require_organisation_editor!, only: %i[update archive restore logo]
      before_action :authorize_organisation_delete!, only: %i[destroy]
      # Membership is delegated rather than admin-only, so it is gated separately
      # from the organisation itself. `set_organisation` runs first, so
      # `@organisation` is available; no `with:` lambda, which would pass the
      # organisation in as an argument the method does not take.
      before_action :require_organisation_membership_manager!,
                    only: %i[member_candidates create_member update_member end_member]

      def index
        organisations = Organisation
                        .with_status(params[:status])
                        .of_type(params[:organisation_type])
                        .ordered
                        .includes(:parent_organisation, :created_by_account, :logo_attachment)
        # `mine=1` narrows to the organisations the caller is an *active* member
        # of. It exists because the group form needs the choices an account can
        # actually make: offering every organisation would list ones the server
        # would refuse on submit. Active only — an ended membership does not let
        # you start a new group for a club you have left. A caller with no Person
        # is a non-member rather than an error, so they simply get none.
        if params[:mine].present?
          mine_ids = OrganisationMembership
                     .active
                     .for_user_subjects(Current.user)
                     .select(:organisation_id)
          organisations = organisations.where(id: mine_ids)
        end

        # `tree=1` returns the whole hierarchy in one response, unpaginated. A tree
        # view has no meaningful page: a child whose parent landed on another page
        # cannot be drawn under it, and a client that walks from the roots silently
        # drops it. The federation tree is a small, bounded domain (federations down
        # to clubs), so the unbounded read is the honest trade here. Every other
        # caller still gets a bounded page.
        records, meta =
          if params[:tree].present?
            all = organisations.to_a
            [ all, { page: 1, per_page: all.size, total: all.size, total_pages: 1 } ]
          else
            paginate(organisations)
          end
        ids = records.map(&:id)
        # One pass of counts for the whole page. See `serialize` for why this is
        # computed here rather than per row.
        child_counts = Organisation.where(parent_organisation_id: ids)
                                   .group(:parent_organisation_id)
                                   .count
        membership_counts = OrganisationMembership.where(organisation_id: ids)
                                                   .group(:organisation_id)
                                                   .count

        render json: {
          data: records.map do |row|
            serialize(row, child_counts: child_counts, membership_counts: membership_counts)
          end,
          meta: meta
        }
      end

      def show
        render json: serialize(@organisation)
      end

      # You add yourself. Distinct from `create_member`, which an officer does to
      # *somebody else* and which is gated on `can_manage_members`: joining is
      # self-service, so it deliberately sits outside that before_action rather
      # than widening it.
      #
      # Role is fixed at `member` and cannot be supplied — self-granting `owner` or
      # `administrator` is precisely the escalation this must not allow. An admin
      # still grants roles afterwards through the roster.
      def join
        account = Current.user&.account
        if account.nil?
          return render json: {
            errors: [ "Your account is not ready to join an organisation." ]
          }, status: :unprocessable_entity
        end

        if @organisation.archived?
          return render json: {
            errors: [ "This organisation is archived and is not accepting members." ]
          }, status: :unprocessable_entity
        end

        existing = @organisation.organisation_memberships.find_by(account: account)

        # Already a member: 409, because the request was well formed and the state
        # is what conflicts. A `pending` row is *recorded but not yet active*, so it
        # counts as already having a seat rather than as a reason to refuse.
        if existing && !existing.ended?
          return render json: {
            error: "You are already a member of this organisation.",
            membership: existing.metadata
          }, status: :conflict
        end

        # Re-joining after an ending reactivates the same row rather than adding a
        # second one, so the earlier stint's history stays on the record — the same
        # rule organisation memberships already follow.
        membership = existing || @organisation.organisation_memberships.build(account: account, memberable: account)
        membership.role = "member"
        membership.status = "active"
        membership.joined_at ||= Time.current
        membership.left_at = nil

        if membership.save
          render json: { membership: membership.metadata }, status: :created
        else
          render json: { errors: membership.errors.full_messages },
                 status: :unprocessable_entity
        end
      end

      def create
        @organisation = Organisation.new(organisation_params)
        @organisation.created_by_account = Current.user.account

        if Organisation.transaction do
             @organisation.save && @organisation.organisation_memberships.create!(
               account: Current.user.account,
               memberable: Current.user.account,
               role: "owner",
               status: "active",
               joined_at: Time.current
             )
           end
          render json: serialize(@organisation), status: :created
        else
          render json: { errors: @organisation.errors.full_messages },
                 status: :unprocessable_entity
        end
      end

      def update
        if @organisation.update(updatable_organisation_params)
          render json: serialize(@organisation)
        else
          render json: { errors: @organisation.errors.full_messages },
                 status: :unprocessable_entity
        end
      end

      # Upload or replace a logo. A dedicated multipart endpoint rather than a
      # branch inside `update`, so that route keeps a single content-type contract
      # — and because purging an existing logo is its own confirmable action.
      def logo
        file = params[:logo]
        return render json: { errors: [ "A logo file is required" ] },
                      status: :unprocessable_entity if file.blank?

        # Remember the blob being replaced. A refused replacement must leave the
        # club with the crest it already had: this action used to purge first and
        # attach second, so uploading an oversized or non-image file destroyed a
        # perfectly good logo and left the club with none at all.
        previous = @organisation.logo.attached? ? @organisation.logo.blob : nil

        @organisation.logo.attach(file)

        if @organisation.save
          # Only now is the old blob genuinely unreferenced, so purging it here
          # cannot lose a file that is still in use.
          previous&.purge
          render json: serialize(@organisation.reload)
        else
          # `attach` saves, and a rejected save rolls back — so the database still
          # points at the previous logo and only the in-memory record is wrong.
          # Put it back in memory, then purge the rejected candidate, whose upload
          # the rolled-back INSERT would otherwise strand in storage.
          candidate = @organisation.logo.blob
          errors = @organisation.errors.full_messages
          @organisation.logo.blob = previous
          candidate.purge if candidate && candidate != previous

          render json: { errors: errors }, status: :unprocessable_entity
        end
      rescue ActiveStorage::FileNotFoundError, ActiveRecord::RecordInvalid => e
        render json: { errors: [ e.message ] }, status: :unprocessable_entity
      rescue *storage_service_errors => e
        # Active Storage uploads the bytes from an `after_commit` hook, not inside
        # the transaction, so a refused upload arrives *after* the database already
        # points at the new blob. Left alone, the club keeps a crest that was never
        # stored — and the replaced blob is never purged, because that line sits
        # after the exception. Put the previous logo back and drop the candidate.
        restore_previous_logo(previous)
        render json: { errors: [ "The logo could not be stored: #{e.message}" ] },
               status: :unprocessable_entity
      end

      # Retire an organisation without destroying it. Children are left in place:
      # archiving a club must not silently detach the academy sitting under it.
      def archive
        unless @organisation.archivable?
          return render json: { errors: [ "This organisation is already archived" ] },
                        status: :unprocessable_entity
        end

        @organisation.update!(status: "archived")

        render json: serialize(@organisation)
      end

      def restore
        unless @organisation.restorable?
          return render json: { errors: [ "This organisation is not archived" ] },
                        status: :unprocessable_entity
        end

        @organisation.update!(status: "active")

        render json: serialize(@organisation)
      end

      # Hard delete, for a mistake rather than for a retirement.
      #
      # Archive is the ordinary way to close an organisation and stays the only way
      # for one that has ever been used. This exists so a club created twice, or a
      # placeholder that was never used, can be removed instead of lingering in the
      # tree forever as a ghost node.
      #
      # The two pre-checks are what make "a mistake" a fact rather than an opinion.
      # 409 rather than 422, because the request was well formed — the *state* is
      # what conflicts. `child_organisations` being `restrict_with_error` remains the
      # backstop for a race between the check and the delete; it would surface as a
      # 422, which is why the explicit check comes first and says something useful.
      def destroy
        blocker = @organisation.deletable_blocker
        if blocker
          return render json: {
            error: "This organisation cannot be deleted: #{blocker.downcase}. Archive it instead."
          }, status: :conflict
        end

        destroyed_id = @organisation.id
        # The logo blob goes with it: `has_one_attached` purges, so a deleted club
        # does not leave its crest in storage forever.
        @organisation.destroy!

        render json: { message: "Organisation deleted", id: destroyed_id }
      end

      # --- membership ---------------------------------------------------------
      #
      # Reading the roster is open to any training manager; changing it is delegated
      # to the organisation's own owner and administrators. Unlike the organisation
      # itself, which is a site-level claim, a club's roster is something its own
      # officers should be able to run.

      def members
        render json: {
          organisation: { id: @organisation.id, name: @organisation.name },
          data: visible_memberships.map(&:metadata)
        }
      end

      # Search subjects that can be added to this organisation's roster. The
      # roster is polymorphic, so the typeahead must be as well: claimed or linked
      # profiles are returned as their canonical Account, while unclaimed player and
      # coach profiles remain selectable as profile memberships.
      def member_candidates
        term = params[:q].to_s.strip
        return render json: { data: [] } if term.length < 2

        candidates = account_member_candidates(term) + profile_member_candidates(PlayerProfile, term) + profile_member_candidates(CoachProfile, term)
        candidates = candidates.uniq { |candidate| [ candidate[:memberable_type], candidate[:memberable_id] ] }
                               .sort_by { |candidate| [ candidate[:display_name].to_s.downcase, candidate[:memberable_type], candidate[:memberable_id] ] }
                               .first(25)

        render json: { data: candidates }
      end

      def create_member
        member = resolve_memberable
        return if performed?

        account = member.is_a?(Account) ? member : nil

        existing = @organisation.organisation_memberships.find_by(memberable: member)
        existing ||= @organisation.organisation_memberships.find_by(account: account) if account

        # Already on the roster: nothing was created, so a 201 here would be a lie.
        # 409 rather than 422, because the request was well-formed — the state is
        # what conflicts.
        if existing && !existing.ended?
          return render json: {
            error: "#{member.try(:full_name).presence || member.try(:email).presence || member.try(:user)&.email_address || member.class.name} is already a member of this organisation",
            membership: existing.metadata
          }, status: :conflict
        end

        # Defaulting to `pending`, not `active`: adding someone to a roster is an
        # invitation, and an invitation is not a grant.
        membership = existing || @organisation.organisation_memberships.build(memberable: member, account: account)
        membership.role = member_params[:role].presence || (existing ? membership.role : "member")
        # Defaulting to `active`. This used to default to `pending` — "adding
        # somebody to a roster is an invitation" — but nothing could ever accept an
        # invitation: there is no acceptance endpoint, no inbox, and for an
        # unclaimed account no channel to respond through at all. So `pending` was
        # an inert state an officer had to clear with a second call, and a pending
        # row could sit between a club and being deletable.
        #
        # An officer recording somebody on their own roster is a record-keeping act,
        # not a request, so it now takes effect. `pending` survives only as an
        # explicit choice meaning "recorded, not yet active".
        membership.status = member_params[:status].presence || "active"

        if membership.save
          render json: membership.metadata, status: :created
        else
          render json: { errors: membership.errors.full_messages },
                 status: :unprocessable_entity
        end
      end

      def update_member
        membership = find_membership
        return if membership.nil?

        membership.role = member_params[:role] if member_params[:role].present?
        membership.status = member_params[:status] if member_params[:status].present?

        if membership.save
          render json: membership.metadata
        else
          render json: { errors: membership.errors.full_messages },
                 status: :unprocessable_entity
        end
      end

      # Leaving is an `ended` status, never a delete: a historical assessment must
      # still be explicable by the membership that existed when it was recorded.
      #
      # An invitation nobody accepted is the single exception — see
      # `OrganisationMembership#withdrawable?`. One response shape either way, with
      # `removed` telling the client whether the row is still there.
      def end_member
        membership = find_membership
        return if membership.nil?

        if membership.withdrawable?
          account_id = membership.account_id
          name = membership.display_name
          membership.destroy!
          render json: { removed: true, account_id: account_id, message: "Invitation to #{name} withdrawn." }
        else
          membership.end!
          render json: { removed: false, membership: membership.metadata }
        end
      rescue ActiveRecord::RecordInvalid => e
        render json: { errors: e.record.errors.full_messages },
               status: :unprocessable_entity
      end

      private

      # A `pending` invitation is visible only to the people who can act on it. An
      # ended membership is visible to anyone who can see the organisation, because
      # hiding it would erase the very history this feature exists to keep.
      def visible_memberships
        scope = @organisation.organisation_memberships.includes(:account, :memberable).ordered
        return scope if manageable_membership?
        return scope.ended if Current.user&.account.nil?

        scope.where(account_id: Current.user.account.id)
      end

      def manageable_membership?
        OrganisationAccess.can_manage_members?(@organisation, Current.user)
      end

      def account_member_candidates(term)
        pattern = "%#{ActiveRecord::Base.sanitize_sql_like(term)}%"
        Account.joins(:contact_detail)
               .where("contact_details.first_name ILIKE :q OR contact_details.last_name ILIKE :q OR CONCAT_WS(' ', contact_details.first_name, contact_details.last_name) ILIKE :q", q: pattern)
               .order("contact_details.last_name", "contact_details.first_name", :id)
               .limit(25)
               .map { |account| member_candidate_payload(account, "Account") }
      end

      def profile_member_candidates(klass, term)
        pattern = "%#{ActiveRecord::Base.sanitize_sql_like(term)}%"
        klass.visible_to(Current.user)
             .active
             .where(account_id: nil)
             .where("display_name ILIKE ?", pattern)
             .order(Arel.sql("LOWER(display_name)"), :id)
             .limit(25)
             .map { |profile| member_candidate_payload(profile, klass.name) }
      end

      def member_candidate_payload(member, type)
        {
          id: "#{type}:#{member.id}",
          memberable_type: type,
          memberable_id: member.id,
          account_id: member.is_a?(Account) ? member.id : nil,
          player_profile_id: member.is_a?(PlayerProfile) ? member.id : nil,
          coach_profile_id: member.is_a?(CoachProfile) ? member.id : nil,
          display_name: member.full_name,
          member_type_label: type.underscore.humanize,
          account_status: member.respond_to?(:account_status) ? member.account_status : (member.claimed? ? "connected" : "unclaimed")
        }
      end

      def find_membership
        membership = @organisation.organisation_memberships
                                          .includes(:account, :memberable)
                                          .find_by(id: params[:membership_id]) if params[:membership_id].present?
        return membership if membership

        member = resolve_memberable_from_params(params)
        return if performed?

        membership = @organisation.organisation_memberships
                                  .includes(:account, :memberable)
                                  .find_by(memberable: member)
        membership ||= @organisation.organisation_memberships
                                      .includes(:account, :memberable)
                                      .find_by(account: member) if member.is_a?(Account)
        return membership if membership

        render json: { errors: [ "That member is not a member of this organisation" ] },
               status: :not_found
        nil
      end

      ALLOWED_MEMBERABLE_TYPES = {
        "Account" => Account,
        "PlayerProfile" => PlayerProfile,
        "CoachProfile" => CoachProfile
      }.freeze

      def resolve_memberable
        member = resolve_memberable_from_params(member_params)
        return member if performed? || member.nil?

        canonical_memberable(member)
      end

      def resolve_memberable_from_params(source)
        if source[:account_id].present?
          account = Account.find_by(id: source[:account_id])
          return account if account

          render json: { errors: [ "Account not found" ] }, status: :not_found
          return nil
        end

        if source[:player_profile_id].present?
          return find_memberable(PlayerProfile, source[:player_profile_id], "Player profile")
        end

        if source[:coach_profile_id].present?
          return find_memberable(CoachProfile, source[:coach_profile_id], "Coach profile")
        end

        member_type = source[:memberable_type].to_s
        member_id = source[:memberable_id]
        unless ALLOWED_MEMBERABLE_TYPES.key?(member_type) && member_id.present?
          render json: { errors: [ "Choose an Account, PlayerProfile, or CoachProfile member" ] },
                 status: :unprocessable_entity
          return nil
        end

        find_memberable(ALLOWED_MEMBERABLE_TYPES.fetch(member_type), member_id, member_type.underscore.humanize)
      end

      def find_memberable(klass, id, label)
        member = klass.find_by(id: id)
        return member if member

        render json: { errors: [ "#{label} not found" ] }, status: :not_found
        nil
      end

      def canonical_memberable(member)
        return member unless member.respond_to?(:account) && member.account.present?

        member.account
      end

      # The failures a storage *service* raises when it will not accept the bytes:
      # an S3-compatible endpoint refusing the request (Cloudflare R2 rejects a
      # request carrying two non-default checksums, see config/storage.yml) or a
      # checksum that does not match what was stored.
      #
      # `aws-sdk-s3` is a lazy dependency (`gem "aws-sdk-s3", require: false`), so
      # its error class is only named when the SDK is actually loaded — which is
      # precisely when an S3-backed service can raise one. In an environment where
      # it is not loaded no such error can occur, and referencing it would only
      # risk an uninitialized-constant error while handling an unrelated exception.
      def storage_service_errors
        [
          ActiveStorage::IntegrityError,
          (Aws::S3::Errors::ServiceError if defined?(Aws::S3::Errors::ServiceError))
        ].compact
      end

      # Undo the database half of a replacement whose upload was refused: re-attach
      # the remembered blob and discard the candidate, whose bytes never reached the
      # service. `previous` is nil for a first logo, where the right answer is no
      # attachment at all. Attaching an existing blob uploads nothing — the case is
      # a no-op in Active Storage — so this cannot fail the same way again.
      def restore_previous_logo(previous)
        candidate = @organisation.logo.blob

        if previous
          @organisation.logo.attach(previous)
          @organisation.save
        else
          @organisation.logo.detach
        end

        candidate.purge if candidate && candidate != previous
      end

      # The host has to be threaded in explicitly: a JSON payload cannot rely on
      # the view helper `url_for` that a server-rendered app would use to build a
      # logo URL, so the absolute URL is assembled here.
      #
      # The permission flags and `child_count` are passed in from the caller when a
      # whole page is being rendered. `Organisation#metadata` can answer every one of
      # them on its own, but that costs two or three queries *per row*, which turns
      # a list of 50 organisations into ~150 queries. Hoisting the counts into a
      # grouped query keeps the list at a fixed cost. Omitted arguments (a single
      # `show`) simply fall back to the per-record queries, which are correct and
      # cheap at that size.
      def serialize(organisation, child_counts: nil, membership_counts: nil)
        organisation.metadata(
          editable_ids: editable_organisation_ids,
          editable_all: editable_all?,
          manage_members_ids: manageable_organisation_ids,
          manage_members_all: Current.user.admin?,
          child_counts: child_counts,
          membership_counts: membership_counts
        )
      end

      # The organisations whose roster the caller may run: a site admin runs every
      # one, and otherwise it is the active owner/administrator memberships. Resolved
      # once for the whole page for the same reason `editable_organisation_ids` is —
      # a per-row check would be one query per organisation in the list.
      def manageable_organisation_ids
        return @manageable_organisation_ids if defined?(@manageable_organisation_ids)
        return @manageable_organisation_ids = Set.new if Current.user.admin?

        account = Current.user&.account
        # A curator, or a coach with no Account, runs nobody's roster. An empty set
        # says so without a per-row query.
        return @manageable_organisation_ids = Set.new if account.nil?

        @manageable_organisation_ids = account.organisation_memberships.active.manageable.pluck(:organisation_id).to_set
      end

      # The scheme the *browser* used, which is not necessarily the one that reached
      # Rails. Behind the production reverse proxy — and behind the Vite dev proxy —
      # TLS is terminated upstream, so `request.protocol` can report `http`. This
      # was needed back when serialised URLs were absolute; the logo is now a
      # relative path and nothing else builds a URL from the request, but the
      # helper stays in case one returns.
      def request_protocol
        request.headers["X-Forwarded-Proto"].presence || request.protocol
      end

      # Oversight can edit *every* organisation, so there is no subset worth
      # computing and the per-row membership lookups are skipped entirely.
      #
      # This is a separate flag rather than a sentinel inside `editable_organisation_ids`
      # because "no ids" and "every id" are opposite answers, and conflating them is
      # what previously sent admins down the per-record path and turned a list of 50
      # organisations into ~150 queries.
      def editable_all?
        return @editable_all if defined?(@editable_all)

        @editable_all = Current.user.admin? || Current.user.curator?
      end

      # The organisations the caller may edit, resolved in a fixed number of queries
      # rather than once per row. Mirrors `Organisation#editable_by?` exactly — the
      # controller test that compares the two keeps them from drifting.
      def editable_organisation_ids
        return Set.new if editable_all?
        return @editable_organisation_ids if defined?(@editable_organisation_ids)

        account = Current.user&.account
        @editable_organisation_ids = account.nil? ? Set.new : membership_ids_for(account)
      end

      def membership_ids_for(account)
        active_ids = account.organisation_memberships.active.pluck(:organisation_id)
        officer_ids = account.organisation_memberships.active.manageable.pluck(:organisation_id)
        return officer_ids.to_set if active_ids.empty?

        officer_ids.to_set
      end

      def set_organisation
        @organisation = Organisation
                        .includes(:parent_organisation, :created_by_account)
                        .find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Organisation not found" }, status: :not_found
      end

      # A member may read the organisation they belong to from their Identity
      # dashboard. Catalogue and management access remain training-manager only.
      def require_organisation_reader!
        return if OrganisationAccess.can_read?(@organisation, Current.user)

        render json: { error: "Forbidden" }, status: :forbidden
      end

      # `status` is writable so a client can archive or restore in one call, but
      # `created_by_account` is deliberately not: attribution is set server-side
      # and is not the caller's to choose.
      def organisation_params
        params.require(:organisation).permit(
          :name, :description, :acronym, :organisation_type, :status, :parent_organisation_id
        )
      end

      # Editing a record and moving it in the tree are different claims. Relaxing
      # `update` from admin-only to include curators, owners and the creator also
      # relaxed re-parenting with it, which let a club rename-and-move a federation
      # node — a claim made *to* every other club, and admin-only by design.
      #
      # Dropped rather than rejected: silently ignoring an unauthorised field is the
      # standard Rails answer, and the SPA does not offer re-parenting outside the
      # create form, so nothing legitimate is lost.
      def updatable_organisation_params
        permitted = organisation_params
        permitted.delete(:parent_organisation_id) unless Current.user&.admin?
        permitted
      end

      def member_params
        params.require(:membership).permit(:account_id, :memberable_type, :memberable_id,
                                           :player_profile_id, :coach_profile_id,
                                           :role, :status)
      end
    end
  end
end
