class DailyDigestJob < ApplicationJob
  queue_as :default

  def perform
    User.find_each do |user|
      next unless user.active_access?
      DigestMailer.daily_digest(user).deliver_later
    end
  end
end
