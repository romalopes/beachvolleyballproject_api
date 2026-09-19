# Video — the actual media resource (a YouTube clip, a Vimeo video, or in the
# future an uploaded S3 file identified by storage_key).
#
# A Video is deliberately standalone and reusable: the *same* clip can back any
# number of VideoReference rows (different Drills/Skills, different relevance
# windows). Provider specifics (embedding, ids, thumbnails) are delegated to
# the VideoProviders classes; the model stores only normalized data.
class Video < ApplicationRecord
  belongs_to :created_by, class_name: "User", optional: true
  has_many :video_references, dependent: :destroy
  has_many :drills, through: :video_references, source: :referenced, source_type: "Drill"
  has_many :skills, through: :video_references, source: :referenced, source_type: "Skill"

  # Detection must run before the other validations: it fills in `provider`,
  # `provider_video_id` and the normalized `source_url`/`thumbnail_url`.
  validate :assign_provider_metadata
  validates :provider, inclusion: { in: %w[youtube vimeo instagram tiktok external s3] }
  validates :provider_video_id,
            uniqueness: { scope: :provider, allow_nil: true,
                          conditions: -> { where.not(provider_video_id: nil) } }

  # Finds a Video previously stored from the same URL (same provider + id, or
  # the same source URL for providers without ids) or creates it. Returns nil
  # when the URL is not a usable video link.
  def self.find_or_create_from_url!(url, attributes = {})
    analysis = VideoProviders.analyze(url)
    return nil if analysis.nil?

    existing =
      if analysis.video_id
        find_by(provider: analysis.provider_name, provider_video_id: analysis.video_id)
      else
        find_by(provider: analysis.provider_name, source_url: analysis.normalized_url)
      end
    return existing if existing

    create!(attributes.merge(source_url: url))
  end

  def provider_class
    VideoProviders.for(provider)
  end

  # --- Playback capabilities (read by the API, never re-derived client-side) ---

  def can_embed?
    provider_class.can_embed?
  end

  def supports_start_timestamp?
    provider_class.supports_start_timestamp?
  end

  def supports_end_timestamp?
    provider_class.supports_end_timestamp?
  end

  def embed_url(start_seconds = nil, end_seconds = nil)
    return nil unless can_embed? && provider_video_id

    provider_class.embed_url(provider_video_id, start_seconds, end_seconds)
  end

  def external_url
    provider_class.external_url(source_url.to_s)
  end

  def provider_label
    provider_class.label
  end

  private

  # Detects the provider from source_url and fills in the normalized identity:
  # provider name, provider id, canonical URL and (when the provider exposes
  # one reliably) the thumbnail. Storage-key-only records (future S3 uploads)
  # skip detection entirely.
  def assign_provider_metadata
    if source_url.blank?
      errors.add(:base, "either source_url or storage_key is required") if storage_key.blank?
      return
    end

    analysis = VideoProviders.analyze(source_url)
    if analysis.nil?
      errors.add(:source_url, "is not a valid video URL")
      return
    end

    self.provider = analysis.provider_name
    self.provider_video_id = analysis.video_id
    self.source_url = analysis.normalized_url
    if thumbnail_url.blank? && analysis.video_id
      self.thumbnail_url = analysis.provider_class.thumbnail_url(analysis.video_id)
    end
  end
end
