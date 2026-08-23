# frozen_string_literal: true

module RailsNexus
  # Abstract base class for all RailsNexus models.
  # Supports connecting to a separate database via configuration.
  #
  # When NO database config is set, this behaves identically to ApplicationRecord.
  # The host app's default connection is used for all queries.
  #
  # Config options:
  #   config.database_url = "mysql2://user:pass@localhost/rails_nexus"
  #   config.database_name = "rails_nexus"   # looks up in config/database.yml
  #   config.database_yml = "config/rails_nexus_database.yml"
  #
  class BaseRecord < ApplicationRecord
    self.abstract_class = true

    class << self
      # Check if a separate database is configured
      def separate_database?
        config = RailsNexus.configuration
        config.database_url.present? || config.database_name.present? || config.database_yml.present?
      end
    end
  end
end
