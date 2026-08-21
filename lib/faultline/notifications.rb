# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module Faultline
  module Notifications
    class << self
      # Called after a LoggedException is created.
      # Triggers webhooks and the after_create callback.
      def notify(exception_record)
        config = Faultline.configuration

        # Custom after_create callback
        config.after_create&.call(exception_record)

        # Webhooks
        notify_webhooks(exception_record) if config.webhooks.any?
      end

      private

      def notify_webhooks(exception_record)
        config = Faultline.configuration
        payload = build_webhook_payload(exception_record)

        config.webhooks.each do |url|
          deliver_webhook(url, payload, config)
        rescue StandardError => e
          Rails.logger.error("[Faultline] Webhook failed for #{url}: #{e.message}")
        end
      end

      def deliver_webhook(url, payload, config)
        uri = URI(url)

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = config.webhook_timeout
        http.read_timeout = config.webhook_timeout

        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        config.webhook_headers.each { |k, v| request[k] = v }
        request.body = payload.to_json

        response = http.request(request)

        unless response.is_a?(Net::HTTPSuccess)
          Rails.logger.error("[Faultline] Webhook #{url} returned #{response.code}")
        end
      end

      def build_webhook_payload(exception_record)
        {
          event: "exception.logged",
          timestamp: exception_record.created_at.iso8601,
          exception: {
            id: exception_record.id,
            class: exception_record.exception_class,
            message: exception_record.message&.truncate(500),
            controller: exception_record.controller_name,
            action: exception_record.action_name,
            remote_ip: exception_record.remote_ip,
            user_agent: exception_record.user_agent
          },
          dashboard_url: dashboard_url(exception_record)
        }
      end

      def dashboard_url(exception_record)
        host = Rails.application.routes.default_url_options[:host] ||
               ENV.fetch("APP_HOST", "localhost:3000")
        protocol = Rails.env.production? ? "https" : "http"
        "#{protocol}://#{host}/faultline/logged_exceptions/#{exception_record.id}"
      end
    end
  end
end
