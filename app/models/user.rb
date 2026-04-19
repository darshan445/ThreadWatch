class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :trackable, :validatable

  has_many :watchers, class_name: "Watcher", dependent: :destroy
  has_many :reply_templates, dependent: :destroy

  before_create :set_trial_period

  def trial_active?
    trial_ends_at? && trial_ends_at > Time.current
  end
  alias on_trial? trial_active?

  def active_account?
    trial_active? || subscribed?
  end
  alias active_access? active_account?

  private

  def set_trial_period
    self.trial_ends_at ||= 7.days.from_now
  end
end
