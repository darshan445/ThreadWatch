require "sidekiq/web"
require "sidekiq/cron/web"

Rails.application.routes.draw do
  mount Sidekiq::Web       => "/sidekiq"
  mount ActionCable.server => "/cable"

  get "up" => "rails/health#show", as: :rails_health_check

  devise_for :users, path_names: {
    sign_in:  "login",
    sign_out: "logout",
    sign_up:  "register"
  }

  root "landing#index"

  authenticate :user do
    get "/dashboard", to: "dashboard#index", as: :dashboard

    resources :watchers do
      if Rails.env.development?
        member { post :run_check }
      end
      resources :leads, only: [:index], module: :watchers
    end

    resources :leads, only: [:show, :update]

    resources :reply_templates, only: [:index, :create, :destroy] do
      member { patch :use }
    end

    get "/pricing", to: "pages#pricing", as: :pricing
  end
end
