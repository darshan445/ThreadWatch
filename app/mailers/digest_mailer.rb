class DigestMailer < ApplicationMailer
  def daily_digest(user)
    @user = user

    watcher_ids = user.watchers.pluck(:id)
    leads_since = 24.hours.ago

    raw_leads = Lead
      .ai_digestable
      .where(watcher_id: watcher_ids, status: "new")
      .where("leads.created_at >= ?", leads_since)
      .includes(:watcher, :raw_post)

    # Group by watcher, sort each group by score desc, cap at 10
    @watcher_leads = raw_leads
      .group_by(&:watcher)
      .transform_values { |leads| leads.sort_by { |l| -l.score }.first(10) }
      .sort_by { |watcher, _| watcher.name }

    @total_count = raw_leads.size
    return if @total_count.zero?

    mail(
      to:      user.email,
      subject: "🎯 #{@total_count} new Reddit lead#{"s" if @total_count != 1} found today"
    )
  end
end
