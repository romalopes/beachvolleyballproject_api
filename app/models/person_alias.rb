# An alternate name under which a Person is known (nickname, alternate
# spelling, transliteration).
#
# Aliases improve duplicate detection during identity resolution; they are
# never proof of identity by themselves.
class PersonAlias < ApplicationRecord
  # `previous_name` is written by Person when a person is renamed, so an old
  # spelling stays findable (and duplicate detection keeps working across a
  # rename). The others are entered by hand.
  ALIAS_TYPES = %w[nickname alternate_spelling transliteration previous_name other].freeze

  belongs_to :person

  validates :full_name, presence: true, length: { maximum: 120 }
  validates :alias_type, inclusion: { in: ALIAS_TYPES }, allow_nil: true
end