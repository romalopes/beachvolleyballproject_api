module Sluggable
  extend ActiveSupport::Concern

  included do
    before_validation :generate_slug, if: :slug_needs_update?
    validates :slug, presence: true, uniqueness: true
  end

  class_methods do
    def source_column(column = nil)
      @source_column = column if column
      @source_column
    end
  end

  private

  def slug_needs_update?
    slug.blank? || source_value_changed?
  end

  def source_value_changed?
    column = self.class.source_column
    return false unless column
    public_send("#{column}_changed?")
  end

  def generate_slug
    column = self.class.source_column
    return unless column
    base = public_send(column).to_s.parameterize
    base = "item" if base.blank?
    self.slug = base
    count = 1
    while slug_taken?
      count += 1
      self.slug = "#{base}-#{count}"
    end
  end

  def slug_taken?
    scope = self.class.where(slug: slug)
    scope = scope.where.not(id: id) if persisted?
    scope.exists?
  end
end