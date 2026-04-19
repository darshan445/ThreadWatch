class LandingController < ApplicationController
  layout "landing"
  skip_before_action :authenticate_user!, raise: false

  def index
    redirect_to dashboard_path if user_signed_in? && current_user.active_account?
  end
end
