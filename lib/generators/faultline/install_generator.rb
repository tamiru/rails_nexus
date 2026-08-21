# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"

module Faultline
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include Rails::Generators::Migration
      include ActiveRecord::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      desc "Install Faultline: creates migration, initializer, and mounts routes."

      def self.next_migration_number(path)
        # Generate timestamp-based migration number for Rails 8.1+ compatibility
        Time.now.utc.strftime("%Y%m%d%H%M%S")
      end

      def create_migration
        migration_template "migration.rb",
                           "db/migrate/create_faultline_logged_exceptions.rb",
                           migration_version: migration_version
      end

      def create_initializer
        template "faultline.rb", "config/initializers/faultline.rb"
      end

      def mount_routes
        route "mount Faultline::Engine => \"/faultline\""
      end

      def include_loggable
        inject_into_class "app/controllers/application_controller.rb", "ActionController::Base" do
          "  include Faultline::ExceptionLoggable\n"
        end
      rescue StandardError
        say "Could not auto-inject ExceptionLoggable into ApplicationController.", :yellow
        say "Add the following to your ApplicationController:\n\n  include Faultline::ExceptionLoggable\n"
      end

      def display_post_install
        say ""
        say "Faultline has been installed!", :green
        say ""
        say "Next steps:"
        say "  1. Run:  bin/rails db:migrate"
        say "  2. Visit: /faultline"
        say ""
        say "Protect the dashboard by editing config/initializers/faultline.rb"
        say ""
      end

      private

      def migration_version
        "[#{ActiveRecord::Migration.current_version}]"
      end
    end
  end
end
