Rails.application.routes.draw do
  resource :session
  resource :registration, only: %i[new create]
  resources :passwords, param: :token
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # UI routes (server-rendered, Hotwire)
  root "home#index"
  get "skills", to: "skills#index"
  get "skills/:id", to: "skills#show", as: :skill
  get "drills", to: "drills#index"
  get "drills/:id", to: "drills#show", as: :drill
  get "videos", to: "videos#index"
  get "training", to: "training_sessions#index"
  get "training/:id", to: "training_sessions#show", as: :training_session
  get "schedule", to: "schedule#index"
  get "account", to: "accounts#show", as: :account
  patch "account", to: "accounts#update"
  patch "account/password", to: "accounts#update_password", as: :account_password

  # Admin
  namespace :admin do
    get "users", to: "users#index"
    post "users/:id/roles", to: "users#add_role", as: :user_add_role
    delete "users/:id/roles/:role", to: "users#remove_role", as: :user_remove_role

    # Admin Settings CRUD (server-rendered views)
    get "settings", to: "dashboard#index", as: :settings
    resources :skills
    resources :categories
    resources :drills
  end

  # API routes
  namespace :api, defaults: { format: :json } do
    namespace :v1 do
      # Auth endpoints (JSON for the React SPA)
      post "registrations", to: "registrations#create"
      post "sessions", to: "sessions#create"
      delete "sessions", to: "sessions#destroy"
      get "me", to: "me#show"
      get "health", to: "health#index"
      get "health/detailed", to: "health#detailed"

      # Private test-access gate (see TestAccessToken): password -> signed
      # token; token verification for the SPA on boot.
      post "test_access", to: "test_access#create"
      get "test_access", to: "test_access#show"
      post "passwords", to: "passwords#create"
      put "passwords/:token", to: "passwords#update"

      # Email verification flow (§3). Available only when EmailVerification.require?
      # is true at runtime — the controller/service already guards this, but the
      # routes are always present so the SPA can call them unconditionally.
      get "email-verifications/:token", to: "email_verifications#show"
      post "email-verifications/resend", to: "email_verifications_resend#create"

      resources :categories
      resources :skills do
        # Videos attached to a Skill; the reference target comes from the
        # nested URL. See VideoReferencesController.
        resources :video_references, only: %i[create update destroy]
      end
      resources :drills do
        # Videos attached to a Drill; same contract as for skills.
        resources :video_references, only: %i[create update destroy]
      end
      resources :training_sessions do
        # Videos attached to a TrainingSession (e.g. a session recording);
        # same contract as for drills and skills.
        resources :video_references, only: %i[create update destroy]
      end
      resources :drill_skills
      resources :video_categories, only: [:index, :show]
      namespace :admin do
        # index is used by the SPA settings pages (usage counts per category).
        # reorder persists the drag-and-drop order.
        resources :video_categories, only: [:index, :create, :update, :destroy] do
          collection { patch :reorder }
        end
      end

      resources :video_tags, only: [:index, :show]
      namespace :admin do
        # index is used by the SPA settings pages (usage counts per tag).
        # reorder persists the drag-and-drop order.
        resources :video_tags, only: [:index, :create, :update, :destroy] do
          collection { patch :reorder }
        end
      end

      resources :videos, only: [:index, :create, :show, :update, :destroy]
      resources :training_sessions

      # Admin role management
      namespace :admin do
        resources :users, only: [:index, :show] do
          post "roles", to: "users#add_role", as: :add_role
          delete "roles/:role", to: "users#remove_role", as: :remove_role
        end

        # Admin Settings CRUD (JSON for the React SPA)
        resources :skills, only: [:index, :show, :create, :update, :destroy]
        resources :categories, only: [:index, :show, :create, :update, :destroy]
        resources :drills, only: [:index, :show, :create, :update, :destroy]

        # Admin audit logs (read-only)
        resources :logs, only: [:index, :show]

        # Admin "Act as User" impersonation
        resource :impersonations, only: %i[create destroy], controller: "impersonations"

        # Tail of the application's Rails log file
        resources :system_logs, only: [:index], defaults: { format: :json }
      end

      resource :account, only: %i[show update], controller: "accounts"
      patch "account/password", to: "accounts#update_password"
    end
  end
end
