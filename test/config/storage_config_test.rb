require "test_helper"

# Guards the checksum options in config/storage.yml.
#
# aws-sdk-s3 >= 1.177 computes a checksum of its own for every upload
# (`request_checksum_calculation` defaults to "when_supported") while Active Storage
# independently sends a Content-MD5. Amazon S3 accepts a request carrying two
# non-default checksums; Cloudflare R2 refuses it with
#
#   Aws::S3::Errors::InvalidRequest: You can only specify one non-default checksum at a time.
#
# The failure is nastier than a plain 500: Active Storage uploads from an
# `after_commit` hook, so the database has already committed the new attachment by
# the time the service refuses the bytes. Delete these keys and every logo upload
# leaves a club pointing at a file that was never stored — see the storage-failure
# tests in test/controllers/api/v1/organisations_controller_test.rb. Both options are
# ordinary SDK client options because Active Storage hands every unrecognised key in
# these blocks to Aws::S3::Resource.
#
# See https://github.com/rails/rails/issues/54374
class StorageConfigTest < ActiveSupport::TestCase
  # The parser Rails itself uses for the file, so ERB is evaluated exactly as it is
  # at boot and the assertions are about the values the service really receives.
  def storage_configurations
    ActiveSupport::ConfigurationFile.parse(Rails.root.join("config/storage.yml"))
  end

  test "every S3-compatible service keeps the SDK from adding a second checksum" do
    s3_services = storage_configurations.select { |_name, config| config["service"] == "S3" }

    assert_predicate s3_services, :any?,
                     "expected at least one service: S3 entry in config/storage.yml — this guard is stale"

    s3_services.each do |name, config|
      assert_equal "when_required", config["request_checksum_calculation"],
                   "#{name} would send the SDK's own checksum alongside Active Storage's Content-MD5"
      assert_equal "when_required", config["response_checksum_validation"],
                   "#{name} would ask the endpoint for checksum-mode downloads it may not answer"
    end
  end

  test "the services the app actually uses are covered by that guard" do
    # A guard over an empty or unrelated set would pass while the service in use
    # breaks, so name the ones the environments select.
    assert_includes storage_configurations.keys, "cloudflare_r2"
    assert_includes storage_configurations.keys, "supabase"

    %w[development production].each do |environment|
      service = Rails.root.join("config/environments/#{environment}.rb").read
      selected = service.scan(/config\.active_storage\.service = :(\w+)/).flatten.reject { |n| n == "local" }
      assert_predicate selected, :any?, "no Active Storage service selected in #{environment}.rb"

      selected.each do |service_name|
        config = storage_configurations.fetch(service_name)
        next unless config["service"] == "S3"
        assert_equal "when_required", config["request_checksum_calculation"],
                     "#{environment} stores files on #{service_name}, which is missing its checksum options"
      end
    end
  end
end
