class DashboardController < AuthenticatedController
  def index
    @watchers        = current_user.watchers.order(created_at: :desc)
    @new_leads_today = Lead.joins(:watcher)
                           .merge(Lead.not_ai_rejected)
                           .where(watchers: { user_id: current_user.id })
                           .where(status: "new", created_at: Time.current.beginning_of_day..)
                           .count
    @total_leads     = Lead.joins(:watcher).where(watchers: { user_id: current_user.id }).count
    @replied_leads   = Lead.joins(:watcher).where(watchers: { user_id: current_user.id }, leads: { status: "replied" }).count
    @recent_leads    = Lead.joins(:watcher, :raw_post)
                           .merge(Lead.not_ai_rejected)
                           .where(watchers: { user_id: current_user.id })
                           .order(created_at: :desc)
                           .limit(8)
                           .includes(:watcher, :raw_post)
  end
end
