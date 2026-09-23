module Api
  module V1
    # Identity search over Person records.
    #
    # This is the lookup the "create player/coach" flow runs *before* creating a
    # new person: a coach searches by name or email, then either picks an
    # existing Person or creates a new one. It returns contact details, so it is
    # limited to staff (coaches/admins) — the same people who may create
    # profiles.
    #
    # The payload is Person#identity_summary, shared with the
    # `possible_duplicates` block returned by Players/Coaches create, so clients
    # render both with one component.
    class PeopleController < ApplicationController
      include ContentAuthorization

      before_action :require_authentication
      before_action :require_content_creator!

      # Bounded so the typeahead stays cheap and cannot be used to dump the
      # whole people table.
      LIMIT = 25

      def index
        people = Person.canonical
                       .includes(:account, :player_profile, :coach_profile, :person_aliases)
                       .order(:last_name, :first_name, :id)

        if params[:q].present?
          term = "%#{params[:q]}%"
          # The alias subquery keeps a renamed person findable by the name a
          # coach still knows them by ("Peter Smith" once "Pedro Silva"), and
          # makes duplicate detection work across a rename.
          people = people.where(
            "people.first_name ILIKE :term OR people.last_name ILIKE :term OR people.email ILIKE :term " \
            "OR people.id IN (SELECT person_id FROM person_aliases WHERE full_name ILIKE :term)",
            term: term
          )
        end
        if params[:email].present?
          people = people.where("LOWER(people.email) = ?", params[:email].to_s.strip.downcase)
        end

        render json: people.limit(LIMIT).map(&:identity_summary)
      end
    end
  end
end
