class WatchersController < AuthenticatedController
  before_action :set_watcher, only: [:show, :edit, :update, :destroy, :run_check]

  def index
    @watchers = current_user.watchers.order(created_at: :desc)
  end

  def show
    redirect_to watcher_leads_path(@watcher)
  end

  def new
    @watcher = current_user.watchers.build
  end

  def create
    @watcher = current_user.watchers.build(watcher_create_params)
    WatcherSetupService.call(@watcher)
    if @watcher.save
      redirect_to edit_watcher_path(@watcher),
                  notice: "Watcher created! AI has generated keywords & subreddits — review and adjust below."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @watcher.update(watcher_params)
      redirect_to watchers_path, notice: "Watcher updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @watcher.destroy
    redirect_to watchers_path, notice: "Watcher deleted."
  end

  # Dev only: enqueue same job as sidekiq-cron (ScheduleWatchersJob fans out to this per watcher).
  def run_check
    head :not_found and return unless Rails.env.development?

    WatcherCheckJob.perform_later(@watcher.id)
    redirect_to watchers_path, notice: "Check queued for \"#{@watcher.name}\" (Sidekiq must be running)."
  end

  private

  def set_watcher
    @watcher = current_user.watchers.find(params[:id])
  end

  # New watcher: user provides name + description only; service populates keywords/subreddits.
  def watcher_create_params
    params.require(:watcher).permit(:name, :description, :active, :fetch_limit, :reddit_time_filter)
  end

  # Edit: user may adjust all fields including AI-generated ones.
  def watcher_params
    params.require(:watcher).permit(:name, :description, :keywords, :subreddits, :active, :fetch_limit, :reddit_time_filter)
  end
end
