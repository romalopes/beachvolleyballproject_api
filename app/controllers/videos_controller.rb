class VideosController < ApplicationController
  allow_unauthenticated_access

  def index
    @videos = Video.includes(:video_references).order(:title)
  end
end
