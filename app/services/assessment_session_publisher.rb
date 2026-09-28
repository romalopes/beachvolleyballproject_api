# Publishes an assessment session: the session's authority (plan S3).
#
# Refuses with 422 when any included player is incomplete, then promotes the
# session and its draft result rows in one transaction (S2). An incomplete roster
# is refused, never partially published, and a total that is missing is never
# coerced to zero (D14).
#
# This lives here rather than in the controller because restoring a withdrawn
# session has to republish it, and a restore must never be more permissive than a
# first publication. One implementation means the two cannot drift.
class AssessmentSessionPublisher
  class Error < StandardError
    attr_reader :errors

    def initialize(errors)
      @errors = Array(errors)
      super(@errors.join(", "))
    end
  end

  def initialize(session)
    @session = session
  end

  def call
    # Publishing accepts a draft only. A withdrawn session is a retraction that
    # only an admin may undo, and `restore` is the single route out of that state;
    # without this guard `publish` would be a second, author-reachable way back.
    unless @session.draft?
      raise Error, "Only a draft session can be published"
    end

    ranking = AssessmentSessionRanking.new(@session).call
    if ranking[:incomplete].any?
      messages = ranking[:incomplete].map do |row|
        "#{row[:player_name]} is missing #{row[:missing_category_ids].size} category score(s)"
      end
      raise Error, [ "Score every included player before publishing" ] + messages
    end

    AssessmentSession.transaction do
      @session.update!(status: "published", published_at: Time.current)
      @session.assessments.where(status: "draft").find_each do |assessment|
        assessment.update!(status: "active")
      end
    end

    @session
  end
end
