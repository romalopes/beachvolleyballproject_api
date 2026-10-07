class RequireUserOnAccounts < ActiveRecord::Migration[8.1]
  def up
    backfill_orphan_accounts!

    change_column_null :accounts, :user_id, false
  end

  def down
    change_column_null :accounts, :user_id, true
  end

  private

  class MigrationAccount < ActiveRecord::Base
    self.table_name = "accounts"
  end

  class MigrationContactDetail < ActiveRecord::Base
    self.table_name = "contact_details"
  end

  class MigrationUser < ActiveRecord::Base
    self.table_name = "users"
  end

  def backfill_orphan_accounts!
    say_with_time "Backfilling users for accounts without user_id" do
      MigrationAccount.where(user_id: nil).find_each do |account|
        contact = MigrationContactDetail.find_by(account_id: account.id)
        email = unique_email_for(account, contact)
        user = MigrationUser.create!(
          email_address: email,
          password_digest: generated_password_digest,
          created_at: Time.current,
          updated_at: Time.current
        )
        account.update!(user_id: user.id, updated_at: Time.current)
      end
    end
  end

  def unique_email_for(account, contact)
    base = contact&.email.presence || "account-#{account.id}@placeholder.invalid"
    return base unless MigrationUser.exists?(email_address: base)

    local, domain = base.split("@", 2)
    domain ||= "placeholder.invalid"
    candidate = "#{local}+account-#{account.id}@#{domain}"
    suffix = 1
    while MigrationUser.exists?(email_address: candidate)
      suffix += 1
      candidate = "#{local}+account-#{account.id}-#{suffix}@#{domain}"
    end
    candidate
  end

  def generated_password_digest
    @generated_password_digest ||= BCrypt::Password.create(SecureRandom.hex(32)).to_s
  end
end
