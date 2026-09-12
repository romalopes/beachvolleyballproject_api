class Session < ApplicationRecord
  belongs_to :user
  belongs_to :impersonated_user, class_name: "User", optional: true
end
