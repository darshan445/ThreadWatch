class PostComment < ApplicationRecord
  belongs_to :raw_post

  validates :comment_id, presence: true, uniqueness: true
  validates :body, presence: true
  validates :depth, inclusion: { in: 0..1 }
end
