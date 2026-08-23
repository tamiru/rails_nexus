# frozen_string_literal: true

module RailsNexus
  class BackupController < ApplicationController
    before_action :rails_nexus_require_auth!
    before_action :check_backup_enabled

    # GET /rails_nexus/backup
    def index
      @service = BackupService.new
      @health = @service.health_status
      @summary = @service.summary
      @records = @service.backup_records
    end

    # GET /rails_nexus/backup/files
    def files
      @service = BackupService.new
      @records = @service.backup_records(limit: 100)
    end

    # POST /rails_nexus/backup/trigger/:model
    def trigger
      @service = BackupService.new
      result = @service.trigger_backup(params[:model])

      if result[:success]
        redirect_to backup_path, notice: "Backup '#{params[:model]}' completed successfully."
      else
        redirect_to backup_path, alert: "Backup failed: #{result[:error]}"
      end
    end

    # DELETE /rails_nexus/backup/:id
    def destroy
      record = RailsNexus::Backup.find(params[:id])
      # Delete the file if it exists
      File.delete(record.file_path) if record.file_path && File.exist?(record.file_path)
      record.destroy
      redirect_to backup_path, notice: "Backup record deleted."
    end

    # GET /rails_nexus/backup/health
    def health
      @service = BackupService.new
      @health = @service.health_status
      @summary = @service.summary
    end

    private

    def check_backup_enabled
      unless RailsNexus.configuration.backup_enabled
        render plain: "Backup management not enabled", status: :forbidden
      end
    end
  end
end
