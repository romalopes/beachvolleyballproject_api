# Shared pagination for the catalogue endpoints.
#
# Mirrors the shape the admin endpoints already return
# (`{ data: [...], meta: { page, per_page, total, total_pages } }`) so the SPA
# can paginate every list with one component and one client helper.
#
# The page size is client-controlled within a sane band: a list screen asks for
# 20, the training form's player picker asks for a page large enough to hold the
# whole roster. Anything outside 1..MAX_PER_PAGE is clamped rather than rejected —
# a bad page number must never be able to dump (or 500 on) the table.
module Pagination
  extend ActiveSupport::Concern

  DEFAULT_PER_PAGE = 20
  MAX_PER_PAGE = 100

  private

  # Returns the requested slice plus the meta block describing it.
  def paginate(scope)
    total = scope.count
    records = scope.offset((page_param - 1) * per_page_param).limit(per_page_param)

    [
      records,
      {
        page: page_param,
        per_page: per_page_param,
        total: total,
        total_pages: total.zero? ? 0 : (total.to_f / per_page_param).ceil
      }
    ]
  end

  def page_param
    page = params[:page].to_i
    page < 1 ? 1 : page
  end

  def per_page_param
    per_page = params[:per_page].to_i
    per_page = DEFAULT_PER_PAGE if per_page < 1
    per_page.clamp(1, MAX_PER_PAGE)
  end
end
