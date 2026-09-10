class LogObject < ApplicationRecord
  belongs_to :log
  belongs_to :object, polymorphic: true

  validates :log, presence: true
  validates :object_type, presence: true
  validates :object_id, presence: true
end
