# frozen_string_literal: true

Stats::Engine.routes.draw do
  root to: "dashboard#index"

  get "login", to: "dashboard#login", as: :login
  post "authenticate", to: "dashboard#authenticate", as: :authenticate
  delete "logout", to: "dashboard#logout", as: :logout

  # JSON API endpoints
  namespace :api do
    get "metrics", to: "metrics#index"
    get "metrics/connections", to: "metrics#connections"
    get "metrics/events", to: "metrics#events"
    get "metrics/system", to: "metrics#system"
  end
end
