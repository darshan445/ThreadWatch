class PagesController < ApplicationController
  layout "dashboard"

  before_action :authenticate_user!

  def pricing
  end
end
