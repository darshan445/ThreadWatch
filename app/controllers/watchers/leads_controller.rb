module Watchers
  class LeadsController < AuthenticatedController
    before_action :set_watcher

    def index
      @status_filter   = params[:status].presence
      @leads           = @watcher.leads.includes(:raw_post)
      @leads           = @leads.where(status: @status_filter) if @status_filter.present?
      @leads           = @leads.not_ai_rejected unless @status_filter == "ignored"
      @leads           = @leads.joins(:raw_post).order("raw_posts.posted_at DESC NULLS LAST, leads.score DESC")
      @reply_templates = current_user.reply_templates.order(use_count: :desc)
    end

    private

    def set_watcher
      @watcher = current_user.watchers.find(params[:watcher_id])
    end
  end
end
