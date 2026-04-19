class RawPost < ApplicationRecord
  SOURCES = %w[reddit g2].freeze

  has_many :post_comments, dependent: :destroy

  validates :source, inclusion: { in: SOURCES }
  validates :external_id, presence: true
  validates :external_id, uniqueness: { scope: :source }

  scope :reddit, -> { where(source: "reddit") }
  scope :g2,     -> { where(source: "g2") }
  scope :unprocessed, -> { where(processed: false) }
end
