class Log < ApplicationRecord
  belongs_to :user, optional: true

  has_many :log_objects, dependent: :destroy

  validates :description, presence: true
  validates :action, presence: true
  validates :method, presence: true

  scope :recent, ->(limit = 50) { order(created_at: :desc).limit(limit) }
  scope :for_action, ->(action) { where(action: action) }
  scope :for_user, ->(user_id) { where(user_id: user_id) }
  scope :for_request, ->(request_id) { where(request_id: request_id) }
  scope :for_object, ->(object_type, object_id) {
    joins(:log_objects).where(log_objects: { object_type: object_type, object_id: object_id })
  }
  scope :in_date_range, ->(start_date, end_date) {
    where(created_at: start_date..end_date) if start_date.present? && end_date.present?
  }
end
