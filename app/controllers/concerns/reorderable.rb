# Shared drag-and-drop reordering for position-ordered admin collections.
#
# The client sends the complete, ordered list of ids for the collection; the
# helper rewrites every row's `position` to its index (0..n-1) inside a single
# transaction. That keeps positions dense and resolves any legacy duplicates
# left over from the days of editing the number by hand.
module Reorderable
  extend ActiveSupport::Concern

  private

  # Rewrites positions for `model`. Renders an error and returns false when the
  # payload is unusable; returns true once the new order is persisted.
  def reorder_records(model)
    ids = reorder_ids(model)
    return false if ids.nil?

    model.transaction do
      ids.each_with_index do |id, index|
        model.where(id: id).update_all(position: index, updated_at: Time.current)
      end
    end
    true
  end

  # Validates the `ids` param: integers, unique, and exactly the full current
  # set (a partial list would silently renumber unrelated rows). Renders and
  # returns nil on failure.
  def reorder_ids(model)
    raw = params[:ids]
    unless raw.is_a?(Array) && raw.all? { |value| value.to_s.match?(/\A\d+\z/) }
      render json: { error: "ids must be an array of integer ids" },
             status: :unprocessable_entity
      return nil
    end

    ids = raw.map(&:to_i)
    if ids.uniq.length != ids.length
      render json: { error: "ids must be unique" }, status: :unprocessable_entity
      return nil
    end

    if ids.length != model.count || model.where(id: ids).count != ids.length
      render json: { error: "ids must list every record exactly once" },
             status: :unprocessable_entity
      return nil
    end

    ids
  end
end
