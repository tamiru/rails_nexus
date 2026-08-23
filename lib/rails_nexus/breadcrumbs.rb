# frozen_string_literal: true

require "active_support/notifications"

module RailsNexus
  # Breadcrumbs capture activity trail before a crash.
  # Uses ActiveSupport::Notifications to subscribe to SQL, controller,
  # cache, and other instrumentation events.
  module Breadcrumbs
    RING_BUFFER_SIZE = 50

    class << self
      # Thread-local ring buffer of breadcrumbs
      def buffer
        Thread.current[:rails_nexus_breadcrumbs] ||= []
      end

      def buffer=(val)
        Thread.current[:rails_nexus_breadcrumbs] = val
      end

      # Capture a breadcrumb manually
      def add(type:, name:, payload: nil, duration: nil)
        buffer << {
          type: type,
          name: name,
          payload: payload,
          duration: duration,
          timestamp: Time.current.iso8601(3)
        }
        # Keep only last N entries
        buffer.shift if buffer.size > RING_BUFFER_SIZE
      end

      # Flush buffer and return captured breadcrumbs
      def flush
        crumbs = buffer.dup
        self.buffer = []
        crumbs
      end

      # Start subscribing to instrumentation events
      def subscribe!
        return if @subscribed

        # SQL queries
        ActiveSupport::Notifications.subscribe("sql.active_record") do |_name, _start, _finish, _id, payload|
          next if payload[:name] == "SCHEMA"
          next if payload[:sql]&.start_with?("SET")
          next if payload[:sql]&.start_with?("SELECT 1")

          add(
            type: "sql",
            name: payload[:sql]&.truncate(200),
            payload: {
              connection_id: payload[:connection_id],
              cached: payload[:cached]
            },
            duration: payload[:runtime]
          )
        end

        # Controller action
        ActiveSupport::Notifications.subscribe("process_action.action_controller") do |_name, _start, _finish, _id, payload|
          add(
            type: "controller",
            name: "#{payload[:controller]}##{payload[:action]}",
            payload: {
              format: payload[:format],
              status: payload[:status],
              view_runtime: payload[:view_runtime]&.round(2),
              db_runtime: payload[:db_runtime]&.round(2)
            },
            duration: payload[:runtime]&.round(2)
          )
        end

        # Cache reads/writes
        ActiveSupport::Notifications.subscribe("cache_read.active_support") do |_name, _start, _finish, _id, payload|
          next unless payload[:hit]  # Only log cache hits

          add(
            type: "cache",
            name: "Cache read: #{payload[:key]}",
            payload: { hit: true, super: payload[:super] }
          )
        end

        ActiveSupport::Notifications.subscribe("cache_write.active_support") do |_name, _start, _finish, _id, payload|
          add(
            type: "cache",
            name: "Cache write: #{payload[:key]}",
            payload: { hit: false }
          )
        end

        # Active Job
        ActiveSupport::Notifications.subscribe("perform_start.active_job") do |_name, _start, _finish, _id, payload|
          add(
            type: "job",
            name: "Job started: #{payload[:job_class]}",
            payload: {
              job_id: payload[:job_id],
              queue: payload[:queue_name],
              arguments: payload[:arguments]&.first(200)
            }
          )
        end

        ActiveSupport::Notifications.subscribe("perform.active_job") do |_name, _start, _finish, _id, payload|
          add(
            type: "job",
            name: "Job completed: #{payload[:job_class]}",
            payload: {
              job_id: payload[:job_id],
              queue: payload[:queue_name],
              error: payload[:exception_object]&.message
            },
            duration: payload[:runtime]&.round(2)
          )
        end

        # Action Mailer
        ActiveSupport::Notifications.subscribe("deliver.action_mailer") do |_name, _start, _finish, _id, payload|
          add(
            type: "mailer",
            name: "Mail delivered: #{payload[:mailer]}##{payload[:message_id]}",
            payload: {
              mailer: payload[:mailer],
              message_id: payload[:message_id]
            }
          )
        end

        # Render partials
        ActiveSupport::Notifications.subscribe("render_partial.action_view") do |_name, _start, _finish, _id, payload|
          add(
            type: "render",
            name: "Render: #{payload[:identifier]}",
            payload: {
              cache_hits: payload[:cache_hit]
            },
            duration: payload[:duration]&.round(2)
          )
        end

        @subscribed = true
      end

      def subscribed?
        @subscribed
      end

      # Reset state (for testing)
      def reset!
        self.buffer = []
        @subscribed = false
      end
    end
  end
end
