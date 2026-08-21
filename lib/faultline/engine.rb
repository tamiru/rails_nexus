# frozen_string_literal: true

module Faultline
  class Engine < ::Rails::Engine
    isolate_namespace Faultline

    engine_name "faultline"

    initializer "faultline.assets", group: :all do |app|
      next unless app.config.respond_to?(:assets) && app.config.assets

      asset_root = root.join("app/assets")

      if defined?(::Propshaft)
        app.config.assets.paths.concat(
          Dir[asset_root.join("*")].select { |path| File.directory?(path) }
        )
      else
        app.config.assets.paths << asset_root
      end
    end

    # Configure Ransack for Faultline models
    initializer "faultline.ransack" do
      ActiveSupport.on_load(:active_record) do
        if defined?(Ransack)
          # Enable Ransack search on LoggedException
          require "faultline/ransack_config"
        end
      end
    end

    # Load notifications and cleanup modules
    initializer "faultline.notifications" do
      require "faultline/notifications"
      require "faultline/cleanup"
    end

    # Register rake tasks
    initializer "faultline.rake_tasks" do
      load "tasks/faultline.rake" if Rake.respond_to?(:application)
    end

    # Hook into LoggedException after_create for notifications
    initializer "faultline.after_create" do
      ActiveSupport.on_load(:active_record) do
        Faultline::LoggedException.after_create do |exception|
          Faultline::Notifications.notify(exception)
        rescue StandardError => e
          Rails.logger.error("[Faultline] Notification error: #{e.message}")
        end
      end
    end
  end
end
