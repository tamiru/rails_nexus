# frozen_string_literal: true

require "rails/generators"
require "rails/generators/erb"

module RailsNexus
  module Generators
    class BackupGenerator < Rails::Generators::Base
      desc "Set up rails_nexus backup directory structure and models"
      source_root File.expand_path("templates/backup", __dir__)

      def create_backup_directories
        empty_directory "config/backup"
        empty_directory "config/backup/models"
        empty_directory "config/backup/mysql-config"
        empty_directory "storage/rails_nexus/backups"
        empty_directory "storage/rails_nexus/backups/sync"
        empty_directory "storage/rails_nexus/backups/logs"
      end

      def create_config_template
        template "config.rb", "config/backup/config.rb"
      end

      def create_model_templates
        template "models/daily_backup.rb", "config/backup/models/daily_backup.rb"
        template "models/full_backup.rb", "config/backup/models/full_backup.rb"
        template "models/sync_backup.rb", "config/backup/models/sync_backup.rb"
      end

      def create_schedule_template
        template "schedule.rb", "config/backup/schedule.rb"
      end

      def create_helper_script
        template "backup_helper.sh", "bin/rails_nexus-backup"
        chmod "bin/rails_nexus-backup", 0o755
      end

      def create_mysql_config
        template "mysql-config/db_config.cnf", "config/backup/mysql-config/db_config.cnf"
      end

      def add_to_gitignore
        append_to_file ".gitignore", <<~GITIGNORE unless File.exist?(".gitignore") && File.read(".gitignore").include?("rails_nexus/backups")
          \n# RailsNexus backups
          storage/rails_nexus/backups/
          config/backup/mysql-config/db_config.cnf
        GITIGNORE
      end

      def show_readme
        say ""
        say "✅ Backup directory structure created!", :green
        say ""
        say "Next steps:"
        say "  1. Edit config/backup/config.rb with your database credentials"
        say "  2. Customize models in config/backup/models/"
        say "  3. Install the schedule: whenever --write-crontab"
        say "  4. Test: bin/rails_nexus-backup status"
        say ""
        say "Backup models created:"
        say "  - daily_backup:  Incremental (skips large tables), local + remote"
        say "  - full_backup:   All tables, local only"
        say "  - sync_backup:   Remote sync to backup server"
        say ""
      end
    end
  end
end
