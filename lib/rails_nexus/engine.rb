# frozen_string_literal: true

module RailsNexus
  class Engine < ::Rails::Engine
    isolate_namespace RailsNexus

    engine_name "rails_nexus"

    # ─── Asset paths (Propshaft and Sprockets) ───

    initializer "rails_nexus.assets", before: "propshaft.assets_middleware", group: :all do |app|
      next unless app.config.respond_to?(:assets)

      # Sprockets 4 only compiles assets listed in a manifest or in the
      # precompile list. Register these here so mounting applications do not
      # need to modify their own asset manifest.
      if app.config.assets.respond_to?(:precompile)
        app.config.assets.precompile += %w[
          rails_nexus/application.css
          rails_nexus/application.js
        ]
      end
    end

    # ─── Database connection (separate DB support) ─────────────────

    initializer "rails_nexus.database" do
      ActiveSupport.on_load(:active_record) do
        config = RailsNexus.configuration

        if config.database_url.present?
          uri = URI.parse(config.database_url)
          RailsNexus::BaseRecord.establish_connection(
            adapter: uri.scheme,
            host: uri.host,
            port: uri.port&.to_i,
            username: URI.decode_www_form_component(uri.user || ""),
            password: URI.decode_www_form_component(uri.password || ""),
            database: uri.path&.gsub(%r{^/}, "")
          )
          Rails.logger.info("[RailsNexus] Connected to separate database: #{config.database_url.split("@").last}") if Rails.logger

        elsif config.database_name.present?
          yaml_path = Rails.root.join("config", "database.yml")
          if yaml_path.exist?
            yaml = YAML.safe_load(ERB.new(yaml_path.read).result, aliases: true) || {}
            env_config = yaml[Rails.env.to_s] || yaml[Rails.env]
            if env_config.is_a?(Hash)
              db_config = env_config.symbolize_keys
              db_config[:database] = config.database_name if config.database_name.is_a?(String)
              RailsNexus::BaseRecord.establish_connection(**db_config)
              Rails.logger.info("[RailsNexus] Connected to database: #{config.database_name}") if Rails.logger
            end
          end

        elsif config.database_yml.present?
          yaml_path = Rails.root.join(config.database_yml)
          if yaml_path.exist?
            yaml = YAML.safe_load(ERB.new(yaml_path.read).result, aliases: true) || {}
            env_config = yaml[Rails.env.to_s] || yaml[Rails.env]
            RailsNexus::BaseRecord.establish_connection(**env_config.symbolize_keys) if env_config.is_a?(Hash)
            Rails.logger.info("[RailsNexus] Connected to database from #{config.database_yml}") if Rails.logger
          end
        end
        # If none configured, BaseRecord inherits ApplicationRecord's connection (default)
      end
    end

    # ─── Ransack configuration ───────────────────────────────────

    initializer "rails_nexus.ransack" do
      ActiveSupport.on_load(:active_record) do
        require "rails_nexus/ransack_config" if defined?(Ransack)
      end
    end

    # ─── Load support modules ─────────────────────────────────────

    initializer "rails_nexus.support" do
      require "rails_nexus/notifications"
      require "rails_nexus/cleanup"
      require "rails_nexus/storm_protection"
    end

    # ─── Rake tasks ──────────────────────────────────────────────

    initializer "rails_nexus.rake_tasks" do
      load "tasks/rails_nexus.rake" if Rake.respond_to?(:application)
    end

    # ─── Hook into after_create for notifications ─────────────────

    initializer "rails_nexus.after_create" do
      ActiveSupport.on_load(:active_record) do
        RailsNexus::LoggedException.after_create do |exception|
          RailsNexus::Notifications.notify(exception)
        rescue StandardError => e
          Rails.logger.error("[RailsNexus] Notification error: #{e.message}")
        end
      end
    end

    # ─── Storm protection ─────────────────────────────────────────

    initializer "rails_nexus.storm_protection" do
      ActiveSupport.on_load(:active_record) do
        require "rails_nexus/storm_protection"
      end
    end

    # ─── Breadcrumbs subscription ─────────────────────────────────

    initializer "rails_nexus.breadcrumbs" do
      ActiveSupport.on_load(:active_record) do
        require "rails_nexus/breadcrumbs"
        if RailsNexus.configuration.breadcrumbs_enabled
          RailsNexus::Breadcrumbs.subscribe!
        end
      end
    end
  end
end
