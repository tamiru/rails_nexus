# frozen_string_literal: true

module RailsNexus
  class CronJobsController < ApplicationController
    before_action :set_cron_job, only: [:show, :destroy]

    def index
      @stats = CronJob.summary
      cron_jobs = CronJob.recent

      if params[:status].present?
        cron_jobs = cron_jobs.by_status(params[:status])
      end

      if params[:name].present?
        cron_jobs = cron_jobs.where(name: params[:name])
      end

      if params[:date_range].present?
        days = params[:date_range].to_i
        cron_jobs = cron_jobs.where("created_at >= ?", days.days.ago)
      end

      requested_size = params[:per_page].to_i
      page_size = requested_size.between?(1, 100) ? requested_size : 30
      @pagy, @cron_jobs = rails_nexus_pagy(cron_jobs, limit: page_size)
    end

    def show
    end

    def destroy
      @cron_job.destroy
      redirect_to cron_jobs_path, notice: "Cron job run deleted."
    end

    def clear_old
      days = params[:days].to_i
      CronJob.where("created_at < ?", days.days.ago).delete_all
      redirect_to cron_jobs_path, notice: "Deleted cron jobs older than #{days} days."
    end

    def retry_job
      cron_job = CronJob.find(params[:id])
      redirect_to cron_jobs_path, notice: "Retrying job: #{cron_job.name}"
    end

    private

    def set_cron_job
      @cron_job = CronJob.find(params[:id])
    end
  end
end
