class ApplicationController < ActionController::Base
  layout :layout_by_resource

  private

  def require_active_account!
    return unless user_signed_in?
    unless current_user.active_account?
      redirect_to pricing_path, alert: "Your trial has ended. Choose a plan to continue."
    end
  end

  def layout_by_resource
    if devise_controller?
      "devise"
    else
      "application"
    end
  end
end
