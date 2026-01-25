# frozen_string_literal: true

Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # NIP-11: Relay info (responds to Accept: application/nostr+json)
  root to: "relay_info#show", constraints: ->(req) {
    req.headers["Accept"]&.include?("application/nostr+json")
  }

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check # rubocop:disable Style/HashSyntax

  # API v1
  namespace :api do
    namespace :v1 do
      resources :upstream_relays, only: %i[index show create update destroy], path: "relays"
      resources :api_keys, only: %i[index create destroy]
    end
  end

  # Defines the root path route ("/")
  # root "posts#index"
end
