require "rails"
require "active_support/parameter_filter"
require "turbo-rails"
require "stimulus-rails"
require "pagy"
require "ipaddr"
require "socket"
require "open3"
require "rails_nexus/version"
require "rails_nexus/configuration"
require "rails_nexus/logger"
require "rails_nexus/database_adapter"
require "rails_nexus/engine"

module RailsNexus
  DEFAULT_FILTER_PARAMETERS = %i[
    password passw passwd secret token api_key apikey authorization cookie session
  ].freeze

  class << self
    attr_writer :configuration

    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    # Backward-compatible accessor for application_name
    def application_name
      configuration.application_name
    end

    def application_name=(value)
      configuration.application_name = value
    end

    # Convenience logger accessor
    def logger
      RailsNexus::Logger
    end

    def parameter_filter
      configured = defined?(::Rails) ? ::Rails.application.config.filter_parameters : []
      ActiveSupport::ParameterFilter.new(DEFAULT_FILTER_PARAMETERS + Array(configured))
    end

    def filter_sensitive_data(value)
      value = value.to_unsafe_h if value.respond_to?(:to_unsafe_h)

      case value
      when Hash
        parameter_filter.filter(value)
      when Array
        value.map { |entry| filter_sensitive_data(entry) }
      else
        value
      end
    end
  end

  # Copyright (c) 2005 Jamis Buck
  #
  # Permission is hereby granted, free of charge, to any person obtaining
  # a copy of this software and associated documentation files (the
  # "Software"), to deal in the Software without restriction, including
  # without limitation the rights to use, copy, modify, merge, publish,
  # distribute, sublicense, and/or sell copies of the Software, and to
  # permit persons to whom the Software is furnished to do so, subject to
  # the following conditions:
  #
  # The above copyright notice and this permission notice shall be
  # included in all copies or substantial portions of the Software.
  #
  # THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
  # EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
  # MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
  # NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
  # LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
  # OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
  # WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
  module ExceptionLoggable
    def self.included(target)
      target.extend(ClassMethods)
      target.class_attribute :local_addresses, :exception_data

      target.local_addresses = [IPAddr.new("127.0.0.1")]
    end

    module ClassMethods
      def consider_local(*args)
        local_addresses.concat(args.flatten.map { |a| IPAddr.new(a) })
      end
    end

    def local_request?
      remote = IPAddr.new(request.remote_ip)
      !self.class.local_addresses.detect { |addr| addr.include?(remote) }.nil?
    end

    # we log the exception and raise it again, for the normal handling.
    def log_exception_handler(exception)
      log_exception(exception) if exception.is_a?(StandardError)
      raise exception
    end

    def rescue_action(exception)
      status = response_code_for_rescue(exception)
      log_exception(exception) if exception.is_a?(StandardError) && status != :not_found
      super
    end

    def log_exception(exception)
      return unless exception.is_a?(StandardError)

      # Support both the legacy class_attribute and the new configuration DSL
      deliverer = if self.class.exception_data
                    self.class.exception_data
                  elsif RailsNexus.configuration.exception_data
                    RailsNexus.configuration.exception_data
                  end

      data = case deliverer
             when nil    then {}
             when Symbol then send(deliverer)
             when Proc   then deliverer.call(self)
             end

      data = RailsNexus.filter_sensitive_data(data || {})

      # Log with structured logger
      RailsNexus::Logger.error(exception, controller: self, extra: data)

      # Create the record
      LoggedException.create_from_exception(self, exception, data)
    end
  end
end

# Compatibility for applications that integrated the exception concern under
# the pre-RailsNexus namespace. New integrations should use
# RailsNexus::ExceptionLoggable.
module RailsOps
  ExceptionLoggable = RailsNexus::ExceptionLoggable unless const_defined?(:ExceptionLoggable, false)
end
