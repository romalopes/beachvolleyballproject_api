Rails.application.routes.draw do
  resource :session
  resource :registration, only: %i[new create]
  resources :passwords, param: :token
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # UI routes (server-rendered, Hotwire)
  root "pages#home"
  get "skills", to: "pages#skills"
  get "skills/:id", to: "pages#skill", as: :skill
  get "drills", to: "pages#drills"
  get "drills/:id", to: "pages#drill", as: :drill
  get "videos", to: "pages#videos"
  get "training", to: "pages#training"
  get "training/:id", to: "pages#training_session", as: :training_session
  get "schedule", to: "pages#schedule"

  # Admin
  namespace :admin do
    get "users", to: "users#index"
    post "users/:id/roles", to: "users#add_role", as: :user_add_role
    delete "users/:id/roles/:role", to: "users#remove_role", as: :user_remove_role
  end

  # API routes
  namespace :api, defaults: { format: :json } do
    namespace :v1 do
      # Auth endpoints (JSON for the React SPA)
      post "registrations", to: "registrations#create"
      post "sessions", to: "sessions#create"
      delete "sessions", to: "sessions#destroy"
      get "me", to: "me#show"
      post "passwords", to: "passwords#create"
      put "passwords/:token", to: "passwords#update"

      resources :categories
      resources :skills
      resources :drills
      resources :drill_skills
      resources :media_assets
      resources :training_sessions

      # Admin role management
      namespace :admin do
        resources :users, only: [:index, :show] do
          post "roles", to: "users#add_role", as: :add_role
          delete "roles/:role", to: "users#remove_role", as: :remove_role
        end
      end
    end
  end
end
