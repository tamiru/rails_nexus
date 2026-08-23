# frozen_string_literal: true

module RailsNexus
  class BackupJob < ApplicationJob
    queue_as :rails_nexus_backups

    # Accept either a BackupConfig record ID or a BackupConfig record
    def perform(backup_config_id_or_record)
      config = if backup_config_id_or_record.is_a?(RailsNexus::BackupConfig)
        backup_config_id_or_record
      else
        RailsNexus::BackupConfig.find(backup_config_id_or_record)
      end

      RailsNexus::BackupService.run(config)
    end
  end
end
