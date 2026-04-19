class LeadsController < AuthenticatedController
  before_action :set_lead, only: [:show, :update]

  def show
    @raw_post        = @lead.raw_post
    @comments        = @raw_post.post_comments.order(score: :desc).limit(10)
    @reply_templates = current_user.reply_templates.order(use_count: :desc)
  end

  def update
    if @lead.update(lead_params)
      respond_to do |format|
        format.turbo_stream do
          @reply_templates = current_user.reply_templates.order(use_count: :desc)
          render turbo_stream: turbo_stream.replace(
            "lead_#{@lead.id}",
            partial: "leads/lead_card",
            locals: { lead: @lead, reply_templates: @reply_templates }
          )
        end
        format.html { redirect_back fallback_location: watcher_leads_path(@lead.watcher), notice: "Lead updated." }
        format.json { render json: { status: @lead.status } }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "lead_#{@lead.id}",
            partial: "leads/lead_card",
            locals: { lead: @lead, reply_templates: current_user.reply_templates.order(use_count: :desc) }
          )
        end
        format.html { render :show, status: :unprocessable_entity }
        format.json { render json: { errors: @lead.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  private

  def set_lead
    @lead = Lead.joins(:watcher).where(watchers: { user_id: current_user.id }).find(params[:id])
  end

  def lead_params
    params.require(:lead).permit(:status, :notes)
  end
end
