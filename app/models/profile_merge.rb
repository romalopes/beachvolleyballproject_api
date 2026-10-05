# Immutable audit of a profile merge. The source profile remains stored and
# points to the canonical profile so old URLs and historical references resolve.
class ProfileMerge < ApplicationRecord
  belongs_to :source_profile, polymorphic: true
  belongs_to :canonical_profile, polymorphic: true
  belongs_to :merged_by_account, class_name: "Account"

  validates :reason, presence: true
  validates :source_profile_id, uniqueness: { scope: :source_profile_type }
  validate :profiles_are_distinct_and_same_kind

  private

  def profiles_are_distinct_and_same_kind
    return unless source_profile_type.present? && canonical_profile_type.present?

    if source_profile_type != canonical_profile_type
      errors.add(:canonical_profile, "must be the same profile type")
    elsif source_profile_id == canonical_profile_id
      errors.add(:canonical_profile, "must differ from the source profile")
    end
  end
end
