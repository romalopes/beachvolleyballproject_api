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

      # Health diagnostics send-test-email tool (Issue 226): read-only config
      # plus a manual, admin-only POST that delivers a one-off message whose
      # subject/body embed the effectively used transport.
      get "health/email/transport", to: "health#email_transport"
      post "health/email/test", to: "health#send_test_email"

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
      resources :video_categories, only: [ :index, :show ]
      namespace :admin do
        # index is used by the SPA settings pages (usage counts per category).
        # reorder persists the drag-and-drop order.
        resources :video_categories, only: [ :index, :create, :update, :destroy ] do
          collection { patch :reorder }
        end
      end

      resources :video_tags, only: [ :index, :show ]
      namespace :admin do
        # index is used by the SPA settings pages (usage counts per tag).
        # reorder persists the drag-and-drop order.
        resources :video_tags, only: [ :index, :create, :update, :destroy ] do
          collection { patch :reorder }
        end
      end

      resources :videos, only: [ :index, :create, :show, :update, :destroy ]

      resources :players, only: %i[index show create update destroy] do
        member { post :merge }
      end
      resources :coaches, only: %i[index show create update destroy] do
        member { post :merge }
      end
      # A read-only account page for the profile catalogues. Editing continues
      # to use the existing singleton `/account` endpoint.
      resources :accounts, only: :show do
        collection { get :search }
      end
      resources :player_claims, only: %i[index show create] do
        collection do
          get :candidates
        end
        member do
          post :approve
          post :reject
          post :cancel
        end
      end
      # Unified claim workflow for player and coach profiles.
      resources :claim_invitations, only: %i[index show create] do
        collection do
          post :redeem
          get :received
          get :claimables
        end
        member do
          post :revoke
          post :accept
          post :decline
        end
      end


      # Who coaches whom: the ongoing coaching relationship between a coach and a
      # player. Deliberately separate from assessments — a coach needs no row here
      # to assess a player, and ending a relationship retracts nothing.
      #
      # No `destroy`: an ended relationship is the context that makes a past
      # assessment explicable, so it is retired with `end_date` instead. `end` is a
      # Ruby keyword, hence `end_relationship` (as `end_member` in organisations).
      resources :player_coaches, only: %i[index show create update] do
        member do
          post :end_relationship
        end
      end
      # A coach's assessment of a player. There is deliberately no `destroy`:
      # a rating is retracted with `PATCH status: "withdrawn"`, never deleted,
      # so `DELETE /api/v1/assessments/:id` is a 404 (phase 4, D18).
      resources :assessments, only: %i[index show create update]

      # Reusable weighted configurations (phase 5): authored once, applied to
      # many players. Deliberately no `destroy` — a definition is `archived`
      # once results quote it, never deleted (ASSESSMENT_DEFINITIONS_PLAN.md).
      # A member route, not a collection: the ids being reordered always belong
      # to one definition, so the definition is part of the URL and `set_definition`
      # (which `reorder` shares with show/update) can resolve it.
      resources :assessment_definitions, only: %i[index show create update destroy] do
        member do
          patch :reorder
          # Retirement is two-tier: archiving hides a configuration reversibly, and
          # is the ordinary action; destroy removes an unused one outright and is
          # admin-only. Both are separate routes so the reversible one is never
          # mistaken for the irreversible one.
          post :archive
          post :restore
        end
      end

      # A hierarchical organisational context: an international federation down to
      # a club, in one self-referencing table.
      #
      # `destroy` exists but is deliberately narrow: admin only, and refused for
      # anything with children or members. An organisation is *archived* to be
      # retired; a hard delete is for a mistake — a club created twice, a
      # placeholder never used — and neither the tree below it nor the membership
      # history of a real club may be destroyed as a side effect of tidying up.
      resources :organisations, only: %i[index show create update destroy] do
        member do
          post :archive
          post :restore
          # Multipart: a file upload rather than JSON. Kept on its own route so
          # `update` keeps a single content-type contract.
          post :logo
          # Membership as a sub-resource of the organisation it belongs to: the
          # person id is in the URL because one person may belong to many
          # organisations, so a person's memberships are never a single record.
          get :members
          # `action:` is required, not decorative: `post :members` would otherwise
          # route to the same `members` action as the GET above and silently
          # answer every write with a 200 and a roster.
          post :members, action: :create_member
          # Distinct `as:` names: two routes cannot share one helper name, and both
          # verbs address the same person.
          patch "members/:account_id", action: :update_member, as: :update_member
          delete "members/:account_id", action: :end_member, as: :end_member
          # Self-service, so it is a separate route rather than another verb on
          # `members`: `post :members` writes somebody *else's* roster row and is
          # gated on `can_manage_members`, while `join` writes your own and must
          # not be.
          post :join
        end
      end

      # `destroy` is scoped to drafts only (a published session is archival, and
      # the controller refuses it with 422 rather than offering a silent delete).
      resources :assessment_sessions, only: %i[index show create update destroy] do
        member do
          post :add_players
          patch :remove_players
          put :scores
          post :publish
          # A withdrawal retracts a published session and is reversible only by an
          # admin, so `restore` is the single route out of the withdrawn state and
          # `publish` deliberately is not.
          post :withdraw
          post :restore
          get :ranking
        end
      end

      # A consolidation is assembled as a draft (its sources may still be being
      # scored) and frozen by `publish`, which requires every source session to be
      # published. A published one is archival, so `destroy` is admin-only; the
      # ordinary retraction is `withdraw`, which is reversible.
      resources :ranking_consolidations, only: %i[index show create update destroy] do
        member do
          post :publish
          post :withdraw
          post :restore
          # The one supervised exception to a published ranking's immutability:
          # rebuild it so a source withdrawn *after* publication stops counting.
          post :recalculate
        end
      end

      # Coach-authored rubrics outside the club catalogue. `PATCH` only: an
      # in-use custom category may not be deleted, and configuration rows are
      # not offered a delete route at all.
      resources :category_customs, only: %i[index show create update]

      # Named rosters (squads/groups) used as reusable participant selections
      # for sessions. Archive-on-delete if used in sessions.
      resources :groups, except: %i[new edit] do
        member do
          post :members, to: "groups#add_members"
          # `:person_id`, not `:player_profile_id`: the roster is keyed on Person
          # (§2.2), so the path segment names what is being removed from it.
          delete "members/:person_id", to: "groups#remove_member"
        end
      end

      resources :training_sessions

      # Admin role management
      namespace :admin do
        resources :users, only: [ :index, :show ] do
          post "roles", to: "users#add_role", as: :add_role
          delete "roles/:role", to: "users#remove_role", as: :remove_role
        end

        # Admin Settings CRUD (JSON for the React SPA)
        resources :skills, only: [ :index, :show, :create, :update, :destroy ]
        resources :categories, only: [ :index, :show, :create, :update, :destroy ]
        resources :drills, only: [ :index, :show, :create, :update, :destroy ]

        # Admin audit logs (read-only)
        resources :logs, only: [ :index, :show ]

        # Admin "Act as User" impersonation
        resource :impersonations, only: %i[create destroy], controller: "impersonations"

        # Global configuration (admin only): singleton settings for the
        # Configuration page — log persistence toggle, test-mode email
        # notifications.
        resource :configuration, controller: "configurations", only: [ :show, :update ]

        # Generic app_settings rows (key/value) for the Configuration page's
        # custom-settings table. Uses the setting key as the identifier.
        resources :app_settings, param: :key, only: [ :index, :create, :update, :destroy ]

        # Tail of the application's Rails log file
        resources :system_logs, only: [ :index ], defaults: { format: :json }
      end

      resource :account, only: %i[show update], controller: "accounts"
      patch "account/password", to: "accounts#update_password"
    end
  end
end
