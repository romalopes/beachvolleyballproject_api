# Public video tags: list (with optional search) + show.
#
# Supports ?search=... for the admin management UI, and returns
# video_count for every tag (including unused ones) so the management page
# and the reference form's picker can offer the full tag vocabulary.
module Api
  module V1
    class VideoTagsController < ApplicationController
      def index
        # left_joins/includes (not joins) so tags with zero videos are still
        # returned — the admin management page and the reference form's picker
        # both need to offer unused tags. video_count comes from the preloaded
        # taggings, so this stays a single extra query.
        scope = VideoTag.includes(:video_taggings).ordered
        scope = scope.where("LOWER(video_tags.name) LIKE ?", "%#{search.downcase}%") if search.present?
        render json: scope, methods: [:video_count]
      end

      def show
        # Tag names are normalized to lowercase in the model, so a name lookup
        # is downcased to match. Numeric ids keep working for existing clients.
        @tag = VideoTag.includes(:videos).find_by(id: params[:id])
        @tag ||= VideoTag.includes(:videos).find_by(name: params[:id].to_s.strip.downcase)
        return render json: { error: "Video tag not found" }, status: :not_found unless @tag

        render json: @tag, methods: [:video_count]
      end

      private

      def search
        params[:search].to_s.strip
      end
    end
  end
end
