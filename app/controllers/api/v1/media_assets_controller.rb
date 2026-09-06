module Api
  module V1
    class MediaAssetsController < ApplicationController
      before_action :set_media_asset, only: [:show, :update, :destroy]

      def index
        @media_assets = MediaAsset.includes(:drill, :skill).all
        render json: @media_assets, include: [:drill, :skill]
      end

      def show
        render json: @media_asset, include: [:drill, :skill]
      end

      def create
        @media_asset = MediaAsset.new(media_asset_params)

        if @media_asset.save
          render json: @media_asset, status: :created
        else
          render json: { errors: @media_asset.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        if @media_asset.update(media_asset_params)
          render json: @media_asset
        else
          render json: { errors: @media_asset.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        @media_asset.destroy
        head :no_content
      end

      private

      def set_media_asset
        @media_asset = MediaAsset.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Media Asset not found" }, status: :not_found
      end

      def media_asset_params
        params.require(:media_asset).permit(:drill_id, :skill_id, :title, :description, :video_url, :asset_type, :thumbnail_url)
      end
    end
  end
end