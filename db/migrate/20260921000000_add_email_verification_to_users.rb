# Configurable email-verification feature on the User model.
#
# Columns:
#   email_verified_at               — when the address was confirmed (NULL = unverified).
#   email_verification_token_digest — SHA-256 digest of the raw token emailed to the user.
#                                     The raw token never touches the database.
#   email_verification_sent_at      — when the last verification email was generated.
#
# Existing users are intentionally NOT backfilled: email_verified_at stays NULL, but
# that does not block them (verification only gates *new* registrations, and only
# when REQUIRE_EMAIL_VERIFICATION=true). A mandatory backfill is a separate feature.
class AddEmailVerificationToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :email_verified_at, :datetime
    add_column :users, :email_verification_token_digest, :string
    add_column :users, :email_verification_sent_at, :datetime
    add_index :users, :email_verification_token_digest
  end
end