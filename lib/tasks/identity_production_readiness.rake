namespace :identity do
  desc "Emit read-only JSON identity migration readiness and preservation counts"
  task production_readiness: :environment do
    report = nil
    ActiveRecord::Base.transaction do
      ActiveRecord::Base.connection.execute("SET TRANSACTION READ ONLY")
      report = IdentityProductionReadinessReport.new.call
    end

    puts JSON.pretty_generate(report)
    abort "Identity readiness report found #{report[:blockers]} blocker(s)." if report[:blockers].positive?
  end
end
