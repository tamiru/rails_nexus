RailsNexus::Engine.routes.draw do
  resources :logged_exceptions do
    collection do
      post :clear
      match :query, via: %i[get post]
      post :destroy_all
      get :feed
    end
    member do
      post :assign, to: "workflow#assign"
      post :set_priority, to: "workflow#set_priority"
      post :snooze, to: "workflow#snooze"
      post :mute, to: "workflow#mute"
      post :unmute, to: "workflow#unmute"
      post :add_comment, to: "workflow#add_comment"
    end
  end

  # Server statistics
  get "stats", to: "stats#index", as: :stats

  # Database health
  get "database_health", to: "database_health#index", as: :database_health

  # Real-time analytics
  get "analytics", to: "analytics#index", as: :analytics

  # Cron job monitoring
  resources :cron_jobs, only: [:index, :show, :destroy] do
    collection do
      delete :clear_old
    end
    member do
      post :retry_job
    end
  end

  # Source code viewing
  get "source_code", to: "source_code#show", as: :source_code

  # N+1 query patterns
  get "n1_patterns", to: "n1_patterns#index", as: :n1_patterns

  # Backup management
  get "backup", to: "backup#index", as: :backup
  get "backup/files", to: "backup#files", as: :backup_files
  post "backup/trigger/:model", to: "backup#trigger", as: :backup_trigger
  delete "backup/:id", to: "backup#destroy", as: :backup_destroy
  get "backup/health", to: "backup#health", as: :backup_health

  # Settings and webhook management
  get "settings", to: "settings#index", as: :settings
  post "settings/test_webhook", to: "settings#test_webhook", as: :test_webhook
  get "settings/deliveries", to: "settings#deliveries", as: :webhook_deliveries

  root :to => 'logged_exceptions#index'
end
