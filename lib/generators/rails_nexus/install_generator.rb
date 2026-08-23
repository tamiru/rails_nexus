# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"

module RailsNexus
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include Rails::Generators::Migration

      MIGRATIONS = {
        "migration.rb" => "create_rails_nexus_exceptions.rb",
        "migration_advanced_features.rb" => "add_advanced_features_to_rails_nexus_exceptions.rb",
        "migration_platform_detection.rb" => "add_platform_to_rails_nexus_exceptions.rb",
        "migration_workflow.rb" => "add_workflow_to_rails_nexus.rb",
        "migration_cron_jobs.rb" => "create_rails_nexus_cron_jobs.rb",
        "migration_webhook_deliveries.rb" => "create_rails_nexus_webhook_deliveries.rb",
        "migration_new_schema.rb" => "create_rails_nexus_metrics_tables.rb"
      }.freeze

      source_root File.expand_path("templates", __dir__)
      desc "Install RailsNexus into your Rails application"

      def self.next_migration_number(dirname)
        ActiveRecord::Generators::Base.next_migration_number(dirname)
      end

      def create_migration_files
        MIGRATIONS.each do |source, destination|
          migration_template source, "db/migrate/#{destination}"
        end
      end

      def create_initializer
        template "rails_nexus.rb", "config/initializers/rails_nexus.rb"
      end

      def mount_routes
        route 'mount RailsNexus::Engine, at: "/rails_nexus"'
      end

      def add_rescue_from
        app_controller = "app/controllers/application_controller.rb"
        destination_controller = File.join(destination_root, app_controller)

        if File.exist?(destination_controller)
          content = File.read(destination_controller)
          unless content.include?("log_exception_handler")
            inject_into_class app_controller, "ApplicationController" do
              "\n  rescue_from Exception, with: :log_exception_handler\n"
            end
          end
        end
      end

      def show_readme
        readme "INSTALL.md" if behavior == :invoke
      end
    end
  end
end
