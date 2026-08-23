# frozen_string_literal: true

module RailsNexus
  class DatabaseHealthController < ApplicationController
    before_action :verify_access

    def index
      @period = params[:period]&.to_i || 7
      @period = [@period, 1].max
      @period = [@period, 90].min

      time_range = @period.days.ago..Time.current

      @pool_by_error = collect_pool_by_error(time_range)
      @summary = collect_summary(time_range)
      @live_pool = collect_live_pool
      @peak_utilization = @pool_by_error.map { |e| e[:utilization] }.max || 0
      @total_dead = @pool_by_error.sum { |e| e[:dead] }
      @total_waiting = @pool_by_error.sum { |e| e[:waiting] }
    end

    private

    def verify_access
      config = RailsNexus.configuration
      return if config.auth_block.nil?
      unless config.auth_block&.call(self)
        render plain: "Forbidden", status: :forbidden
      end
    end

    def collect_pool_by_error(time_range)
      # Get all errors with system_health data in the time range
      exceptions = LoggedException.where(created_at: time_range)
        .where.not(system_health: nil)
        .order(created_at: :desc)

      errors_with_pool = []

      exceptions.find_each do |exception|
        health = parse_health(exception.system_health)
        next unless health&.dig(:db_pool)

        pool = health[:db_pool]
        next if pool[:error]

        errors_with_pool << {
          id: exception.id,
          exception_class: exception.exception_class,
          utilization: pool[:utilization] || 0,
          busy: pool[:busy] || 0,
          idle: pool[:idle] || 0,
          dead: pool[:dead] || 0,
          waiting: pool[:waiting] || 0,
          pool_size: pool[:size] || 0,
          last_seen: exception.created_at
        }
      end

      # Sort by utilization descending
      errors_with_pool.sort_by { |e| -e[:utilization] }
    end

    def collect_summary(time_range)
      exceptions = LoggedException.where(created_at: time_range)
        .where.not(system_health: nil)

      total_errors = exceptions.count
      errors_with_pool = 0
      total_utilization = 0
      max_utilization = 0

      exceptions.find_each do |exception|
        health = parse_health(exception.system_health)
        next unless health&.dig(:db_pool)
        next if health[:db_pool][:error]

        errors_with_pool += 1
        utilization = health[:db_pool][:utilization] || 0
        total_utilization += utilization
        max_utilization = [max_utilization, utilization].max
      end

      {
        total_errors: total_errors,
        errors_with_pool: errors_with_pool,
        avg_utilization: errors_with_pool > 0 ? (total_utilization / errors_with_pool).round(1) : 0,
        max_utilization: max_utilization
      }
    end

    def collect_live_pool
      pool = ActiveRecord::Base.connection_pool
      connections = pool.connections
      active_conns = connections.select(&:active?)
      idle_conns = connections.reject(&:active?)

      dead_count = 0
      begin
        dead_count = pool.instance_variable_get(:@dead_connections)&.size || 0
      rescue StandardError
        # Ignore
      end

      waiting = pool.instance_variable_get(:@waiters)&.size || 0 rescue 0

      {
        size: pool.size,
        connections: connections.size,
        active: active_conns.size,
        busy: active_conns.size,
        idle: idle_conns.size,
        dead: dead_count,
        waiting: waiting,
        utilization: pool.size > 0 ? (connections.size.to_f / pool.size * 100).round(1) : 0,
        adapter: ActiveRecord::Base.connection.adapter_name
      }
    rescue StandardError => e
      { error: e.message }
    end

    def parse_health(data)
      return nil if data.blank?
      return data if data.is_a?(Hash)
      JSON.parse(data, symbolize_names: true) rescue nil
    end
  end
end
