namespace :identity do
  desc "Report the retired Phase 2 Account identity backfill state (read-only)"
  task phase2_backfill: :environment do
    result = AccountIdentityPhase2Backfill.new.call
    puts JSON.pretty_generate(result)
  end
end
