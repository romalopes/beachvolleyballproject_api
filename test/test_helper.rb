ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "test_helpers/session_test_helper"
require_relative "test_helpers/drill_definition_test_helper"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures for current-schema tables in alphabetical order.
    #
    # A previous identity model used people/person_aliases fixtures. The current
    # schema is Account-keyed, so loading those orphaned fixture files would fail
    # before any test can run.
    fixtures(*Dir[Rails.root.join("test/fixtures/*.yml")]
      .map { |path| File.basename(path, ".yml") }
      .excluding("people", "person_aliases")
      .map(&:to_sym))

    # Add more helper methods to be used by all tests here...
    include DrillDefinitionTestHelper

    def create_account!(first_name: "Test", last_name: "Account", email: nil, password: "password123", **account_attributes)
      email ||= "account-#{SecureRandom.hex(8)}@example.com"
      user = User.create!(email_address: email, password: password, email_verified_at: Time.current)
      Account.create!(
        { user: user,
          contact_detail: ContactDetail.new(first_name: first_name, last_name: last_name, email: email) }
          .merge(account_attributes)
      )
    end
  end
end
