class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MAILER_FROM", "RedditLeads <noreply@redditeleads.com>")
  layout "mailer"
end
