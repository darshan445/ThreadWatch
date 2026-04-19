class ReplyTemplate < ApplicationRecord
  belongs_to :user

  validates :name, presence: true
  validates :body, presence: true

  scope :by_usage, -> { order(use_count: :desc) }

  def increment_use!
    increment!(:use_count)
  end
end
