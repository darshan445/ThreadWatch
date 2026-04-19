class AuthenticatedController < ApplicationController
  layout "dashboard"

  before_action :authenticate_user!
  before_action :require_active_account!
end
