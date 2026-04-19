class ReplyTemplatesController < AuthenticatedController
  before_action :set_template, only: [:destroy, :use]

  def index
    @reply_templates = current_user.reply_templates.order(use_count: :desc, created_at: :desc)
    @reply_template  = current_user.reply_templates.build
  end

  def create
    @reply_template = current_user.reply_templates.build(template_params)
    @reply_templates = current_user.reply_templates.order(use_count: :desc, created_at: :desc)

    if @reply_template.save
      redirect_to reply_templates_path, notice: "Template \"#{@reply_template.name}\" created."
    else
      @reply_templates = current_user.reply_templates.order(use_count: :desc, created_at: :desc)
      render :index, status: :unprocessable_entity
    end
  end

  def destroy
    @reply_template.destroy
    redirect_to reply_templates_path, notice: "Template deleted."
  end

  def use
    @reply_template.increment_use!
    head :ok
  end

  private

  def set_template
    @reply_template = current_user.reply_templates.find(params[:id])
  end

  def template_params
    params.require(:reply_template).permit(:name, :body)
  end
end
