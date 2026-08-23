# frozen_string_literal: true

module RailsNexus
  class BackupController < ApplicationController
    before_action :verify_access
    before_action :check_backup_enabled

    # GET /rails_nexus/backup
    def index
      @backup_service = BackupService.new
      @health = @backup_service.health_status
      @summary = @backup_service.summary
      @models = @backup_service.models
      @schedule = @backup_service.cron_schedule
      @records = @backup_service.backup_records
    end

    # POST /rails_nexus/backup/scan
    def scan
      @backup_service = BackupService.new
      created = @backup_service.scan_and_record!
      redirect_to backup_path, notice: "Scanned filesystem — #{created} new backup records created."
    end

    # GET /rails_nexus/backup/files
    def files
      @backup_service = BackupService.new
      @files = @backup_service.backup_files
    end

    # POST /rails_nexus/backup/trigger/:model
    def trigger
      @backup_service = BackupService.new
      result = @backup_service.trigger_backup(params[:model])

      if result[:success]
        redirect_to backup_path, notice: "Backup '#{params[:model]}' triggered (PID: #{result[:pid]})"
      else
        redirect_to backup_path, alert: "Failed: #{result[:error]}"
      end
    end

    # GET /rails_nexus/backup/health
    def health
      @backup_service = BackupService.new
      @health = @backup_service.health_status
      @summary = @backup_service.summary
    end

    # GET /rails_nexus/backup/settings
    def settings
      @backup_config = BackupService.load_config
    end

    # PATCH /rails_nexus/backup/settings
    def update_settings
      result = BackupService.save_config(backup_settings_params)

      if result[:success]
        redirect_to backup_settings_path, notice: "Backup settings saved successfully."
      else
        redirect_to backup_settings_path, alert: "Failed to save: #{result[:error]}"
      end
    end

    private

    def verify_access
      config = RailsNexus.configuration
      return if config.auth_block.nil?
      unless config.auth_block&.call(self)
        render plain: "Forbidden", status: :forbidden
      end
    end

    def check_backup_enabled
      unless RailsNexus.configuration.backup_enabled
        render plain: "Backup management not enabled", status: :forbidden
      end
    end

    def backup_settings_params
      params.require(:backup_config).permit(
        :enabled,
        :config_path,
        :models_path,
        :dump_path,
        :notify_command,
        :alert_threshold_hours,
        :rsync_host,
        :rsync_port,
        :rsync_user,
        :rsync_path,
        :encrypt_password,
        :auto_cleanup_days
      )
    end
  end
end
