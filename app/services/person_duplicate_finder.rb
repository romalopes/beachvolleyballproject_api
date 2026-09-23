# Finds Person records that may already describe the person a coach is about
# to create.
#
# Results are *suggestions* for the UI: the system never merges automatically,
# because a name is not reliable identity evidence and an email can be shared,
# recycled or mistyped (see the identity plan, "Avoid duplicate people").
#
# Signal strength, strongest first:
#   * email    — exact match, case-insensitive;
#   * name     — first and last name both match, case-insensitive.
#
# Merged people are excluded (`Person.canonical`): a duplicate that was already
# consolidated must not be offered again.
class PersonDuplicateFinder
  # Enough to show a short "did you mean…" list without turning the create
  # response into an address book.
  LIMIT = 5

  def initialize(first_name: nil, last_name: nil, email: nil)
    @first_name = first_name.to_s.strip
    @last_name = last_name.to_s.strip
    @email = email.to_s.strip.downcase
  end

  # People that look like the same human, strongest signal first.
  def matches
    scopes = []
    scopes << email_matches if @email.present?
    scopes << name_matches if name_present?
    return [] if scopes.empty?

    scopes
      .reduce { |combined, scope| combined.or(scope) }
      .includes(:account, :player_profile, :coach_profile, :person_aliases)
      .order(:last_name, :first_name, :id)
      .limit(LIMIT)
      .to_a
  end

  private

  def email_matches
    Person.canonical.where("LOWER(people.email) = ?", @email)
  end

  def name_matches
    Person.canonical.where(
      "LOWER(people.first_name) = ? AND LOWER(people.last_name) = ?",
      @first_name.downcase,
      @last_name.downcase
    )
  end

  def name_present?
    @first_name.present? && @last_name.present?
  end
end
