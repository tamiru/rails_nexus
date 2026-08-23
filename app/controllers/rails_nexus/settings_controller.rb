# frozen_string_literal: true

module RailsNexus
  class SettingsController < ApplicationController
    def index
      @webhooks = RailsNexus.configuration.webhooks || []
      @webhook_headers = RailsNexus.configuration.webhook_headers || {}
      @webhook_timeout = RailsNexus.configuration.webhook_timeout || 5
      @recent_deliveries = WebhookDelivery.recent.limit(20)
      @delivery_stats = WebhookDelivery.summary
    end

    def test_webhook
      url = params[:url]
      if url.blank?
        redirect_to settings_path, alert: "URL is required."
        return
      end

      payload = build_test_payload
      result = deliver_test_webhook(url, payload)

      if result[:success]
        redirect_to settings_path, notice: "Webhook test successful! Response: #{result[:status_code]}"
      else
        redirect_to settings_path, alert: "Webhook test failed: #{result[:error]}"
      end
    end

    def deliveries
      @deliveries = WebhookDelivery.recent.limit(25).offset(((params[:page] || 1).to_i - 1) * 25)

      if params[:status].present?
        @deliveries = @deliveries.by_status(params[:status])
      end

      if params[:url].present?
        @deliveries = @deliveries.where(url: params[:url])
      end
    end

    private

    def build_test_payload
      {
        event: "webhook.test",
        timestamp: Time.current.iso8601,
        message: "This is a test webhook from RailsNexus",
        exception: {
          class: "TestException",
          message: "This is a test exception for webhook verification",
          controller: "rails_nexus/settings",
          action: "test_webhook"
        }
      }
    end

    def deliver_test_webhook(url, payload)
      RailsNexus::WebhookClient.deliver(url: url, payload: payload, timeout: 10)
    end
  end
end
