class AdminActivity < ApplicationRecord
  belongs_to :user
  validates :action, inclusion: { in: %w[create update destroy] }
  validates :entity_type, presence: true
  validates :entity_id, presence: true
  scope :for_entity, ->(entity_type, entity_id) { where(entity_type: entity_type, entity_id: entity_id) }
  scope :recent, ->(limit = 50) { order(created_at: :desc).limit(limit) }
end
