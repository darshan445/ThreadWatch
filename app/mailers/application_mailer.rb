class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MAILER_FROM", "ThreadWatch <noreply@threadwatch.com>")
  layout "mailer"
end
