module RailsNexus
  class Comment < ActiveRecord::Base
    self.table_name = "rails_nexus_comments"

    belongs_to :logged_exception, counter_cache: :comments_count

    validates :author, presence: true
    validates :body, presence: true

    scope :recent, -> { order(created_at: :desc) }
    scope :by_type, ->(type) { where(comment_type: type) }
  end
end
