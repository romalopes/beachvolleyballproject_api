Rails.application.routes.draw do
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

  # API routes
  namespace :api do
    namespace :v1 do
      resources :categories
      resources :skills
      resources :drills
      resources :drill_skills
      resources :media_assets
      resources :training_sessions
    end
  end
end
