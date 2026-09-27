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
      before_action :require_training_manager!
      before_action :require_content_creator!, only: %i[create update destroy add_members remove_member]
      before_action :set_group, only: %i[show update destroy add_members remove_member]
      before_action :check_visibility!, only: %i[show update destroy add_members remove_member]
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

        if @group.save
          if params[:player_profile_ids].present?
            assign_player_profile_ids(Array(params[:player_profile_ids]))
          end

          render json: { group: serialize_detail(@group.reload) }, status: :created
        else
          render json: { errors: @group.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        if @group.update(group_params)
          if params.key?(:player_profile_ids)
            sync_player_profile_ids(Array(params[:player_profile_ids]))
          end

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

      # Add one or more players to the group's roster
      def add_members
        ids = Array(params[:player_profile_ids] || params[:player_profile_id]).compact.map(&:to_i)
        if ids.empty?
          return render json: { errors: [ "No players specified" ] }, status: :unprocessable_entity
        end

        added = assign_player_profile_ids(ids)

        render json: {
          group: serialize_detail(@group.reload),
          added: added
        }
      end

      # Remove a single player from the group's roster
      def remove_member
        player_id = params[:player_profile_id].to_i
        membership = @group.group_memberships.find_by(player_profile_id: player_id)

        unless membership
          return render json: { errors: [ "Player is not a member of this group" ] }, status: :not_found
        end

        membership.destroy!

        render json: {
          group: serialize_detail(@group.reload),
          removed: player_id
        }
      end

      private

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
        @group = Group.includes(:created_by, group_memberships: { player_profile: :person })
                      .find_by(id: params[:id]) ||
                 Group.includes(:created_by, group_memberships: { player_profile: :person })
                      .find_by!(slug: params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Group not found" }, status: :not_found
      end

      def check_visibility!
        return if @group.nil?
        return if @group.visible_to_user?(Current.user)

        render json: { error: "Group not found" }, status: :not_found
      end

      def authorize_owner!
        return if @group.nil?
        return if Current.user&.admin? || @group.owner?(Current.user)

        render json: { error: "Forbidden" }, status: :forbidden
      end

      def group_params
        params.require(:group).permit(:name, :description, :visibility, :status)
      end

      def assign_player_profile_ids(ids)
        existing = @group.group_memberships.pluck(:player_profile_id).to_set
        new_ids = ids.uniq.reject { |id| existing.include?(id) }
        valid_players = PlayerProfile.where(id: new_ids)

        created_count = 0
        valid_players.each do |player|
          @group.group_memberships.create!(player_profile: player)
          created_count += 1
        end
        created_count
      end

      def sync_player_profile_ids(ids)
        target_ids = ids.map(&:to_i).uniq.to_set
        valid_players = PlayerProfile.where(id: target_ids.to_a)
        valid_ids = valid_players.pluck(:id).to_set

        # Remove ones not in target
        @group.group_memberships.where.not(player_profile_id: valid_ids.to_a).destroy_all

        # Add new ones
        existing = @group.group_memberships.pluck(:player_profile_id).to_set
        (valid_ids - existing).each do |player_id|
          @group.group_memberships.create!(player_profile_id: player_id)
        end
      end

      def serialize_summary(group)
        group.metadata
      end

      def serialize_detail(group)
        members = group.group_memberships.sort_by(&:id).map do |m|
          player = m.player_profile
          person = player&.person
          {
            id: m.id,
            player_profile_id: m.player_profile_id,
            player_name: m.player_name || person&.full_name,
            level: player&.level,
            preferred_position: player&.preferred_position,
            email: person&.email,
            status: player&.status,
            joined_at: m.created_at
          }
        end

        group.metadata.merge(
          members: members,
          players: members
        )
      end
    end
  end
end
