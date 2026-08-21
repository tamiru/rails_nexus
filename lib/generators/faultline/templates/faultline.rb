# frozen_string_literal: true

Rails.application.config.to_prepare do
  Faultline.configure do |config|
    # Dashboard title shown in the header.
    # config.application_name = "MyApp"

    # Protect the dashboard. Return true to allow access, false to deny.
    # Replace with your app's authentication method.
    #
    # Examples:
    #
    #   # Require admin user (Devise / custom auth)
    #   config.auth_block = ->(controller) { controller.current_user&.admin? }
    #
    #   # Require any logged-in user
    #   config.auth_block = ->(controller) { controller.current_user.present? }
    #
    #   # HTTP Basic Auth (set FAULTLINE_USER / FAULTLINE_PASSWORD env vars)
    #   config.auth_block = ->(controller) {
    #     authenticate_or_request_with_http凭据("Faultline") do |username, password|
    #       username == ENV["FAULTLINE_USER"] && password == ENV["FAULTLINE_PASSWORD"]
    #     end
    #   }
    #
    # ⚠️  Without an auth_block, the dashboard is OPEN to anyone.
    # Uncomment and configure one of the examples above before deploying.
    config.auth_block = ->(controller) { true }

    # Attach extra data to each exception record.
    # config.exception_data = ->(controller) {
    #   {
    #     user_id: controller.current_user&.id,
    #     request_id: controller.request.request_id
    #   }
    # }

    # Number of exceptions per page.
    # config.per_page = 30
  end
end

# Rails 8+ compatibility: Faultline's old rescue_action pattern doesn't work
# anymore. This registers rescue_from to log exceptions via log_exception_handler.
#
# Remove this block if you have your own global exception logging.
ApplicationController.class_eval do
  rescue_from Exception, with: :log_exception_handler
end
