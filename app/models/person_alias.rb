# An alternate name under which a Person is known (nickname, alternate
# spelling, transliteration).
#
# Aliases improve duplicate detection during identity resolution; they are
# never proof of identity by themselves.
class PersonAlias < ApplicationRecord
  ALIAS_TYPES = %w[nickname alternate_spelling transliteration other].freeze

  belongs_to :person

  validates :full_name, presence: true, length: { maximum: 120 }
  validates :alias_type, inclusion: { in: ALIAS_TYPES }, allow_nil: true
end