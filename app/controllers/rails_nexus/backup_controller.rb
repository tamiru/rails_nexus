# frozen_string_literal: true

module RailsNexus
  class BackupController < ApplicationController
    before_action :rails_nexus_require_auth!
    before_action :check_backup_enabled
    before_action :set_config, only: %i[edit update destroy trigger]

    # GET /rails_nexus/backup
    def index
      @configs = RailsNexus::BackupConfig.order(:name)
      @records = RailsNexus::Backup.order(started_at: :desc).limit(20)
      @stats = {
        total_configs: RailsNexus::BackupConfig.count,
        enabled_configs: RailsNexus::BackupConfig.enabled.count,
        total_backups: RailsNexus::Backup.count,
        successful: RailsNexus::Backup.successful.count,
        failed: RailsNexus::Backup.failed.count
      }
    end

    # GET /rails_nexus/backup/new
    def new
      @config = RailsNexus::BackupConfig.new(
        adapter: "mysql",
        host: "localhost",
        port: 3306,
        storage_path: "~/dumps",
        keep_count: 30,
        compress: true
      )
    end

    # POST /rails_nexus/backup
    def create
      @config = RailsNexus::BackupConfig.new(config_params)

      if @config.save
        redirect_to backup_path, notice: "Backup config '#{@config.name}' created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    # GET /rails_nexus/backup/:id/edit
    def edit; end

    # PATCH /rails_nexus/backup/:id
    def update
      if @config.update(config_params)
        redirect_to backup_path, notice: "Backup config '#{@config.name}' updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # DELETE /rails_nexus/backup/:id
    def destroy
      name = @config.name
      @config.destroy
      redirect_to backup_path, notice: "Backup config '#{name}' deleted."
    end

    # POST /rails_nexus/backup/:id/trigger
    def trigger
      result = RailsNexus::BackupService.run(@config)

      if result[:success]
        redirect_to backup_path, notice: "Backup '#{@config.name}' completed successfully."
      else
        redirect_to backup_path, alert: "Backup failed: #{result[:error]}"
      end
    end

    # GET /rails_nexus/backup/:id/history
    def history
      @config = RailsNexus::BackupConfig.find(params[:id])
      @records = RailsNexus::Backup.where(model_name: @config.name)
        .order(started_at: :desc)
        .limit(50)
    end

    # GET /rails_nexus/backup/history
    def all_history
      @records = RailsNexus::Backup.order(started_at: :desc).limit(100)
    end

    private

    def set_config
      @config = RailsNexus::BackupConfig.find(params[:id])
    end

    def config_params
      params.require(:backup_config).permit(
        :name, :description, :database_name, :adapter, :host, :port,
        :username, :password, :storage_path, :keep_count,
        :compress, :encrypted, :encryption_password,
        :rsync_enabled, :rsync_host, :rsync_port, :rsync_user, :rsync_path, :rsync_mirror,
        :notify_command, :notify_on_success, :notify_on_failure,
        :schedule_cron, :enabled,
        :s3_enabled, :s3_access_key, :s3_secret_key, :s3_bucket, :s3_region, :s3_prefix,
        :gpg_enabled, :gpg_password,
        :email_notify, :email_to,
        :archive_enabled, :bzip2_compress, :split_chunks,
        skip_tables: [], archive_paths: [], archive_excludes: []
      )
    end

    def check_backup_enabled
      unless RailsNexus.configuration.backup_enabled
        render plain: "Backup management not enabled", status: :forbidden
      end
    end
  end
end
