namespace :identity do
  desc "Report or repeat the Phase 2 Account identity backfill"
  task phase2_backfill: :environment do
    dry_run = !ActiveModel::Type::Boolean.new.cast(ENV.fetch("APPLY", "false"))
    result = AccountIdentityPhase2Backfill.new.call(dry_run: dry_run)
    puts JSON.pretty_generate(result)
  end
end
