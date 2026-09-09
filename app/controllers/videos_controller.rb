class VideosController < ApplicationController
  allow_unauthenticated_access

  def index
    @videos = MediaAsset.includes(:drill).order(:title)
  end
end