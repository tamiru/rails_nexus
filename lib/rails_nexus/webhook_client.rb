# frozen_string_literal: true

require "ipaddr"
require "json"
require "net/http"
require "openssl"
require "socket"
require "uri"

module RailsNexus
  class WebhookClient
    class ValidationError < StandardError; end

    BLOCKED_NETWORKS = %w[
      0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16
      172.16.0.0/12 192.0.0.0/24 192.0.2.0/24 192.168.0.0/16
      198.18.0.0/15 198.51.100.0/24 203.0.113.0/24 224.0.0.0/4 240.0.0.0/4
      ::/128 ::1/128 ::ffff:0:0/96 100::/64 2001:db8::/32 fc00::/7 fe80::/10 ff00::/8
    ].map { |network| IPAddr.new(network) }.freeze

    def self.deliver(url:, payload:, headers: {}, timeout: nil)
      new(url: url, payload: payload, headers: headers, timeout: timeout).deliver
    end

    def self.redacted_url(url)
      uri = URI.parse(url.to_s)
      return "invalid-webhook-url" if uri.host.blank?

      port = uri.port && uri.port != uri.default_port ? ":#{uri.port}" : ""
      "#{uri.scheme}://#{uri.host}#{port}/[REDACTED]"
    rescue URI::InvalidURIError
      "invalid-webhook-url"
    end

    def initialize(url:, payload:, headers: {}, timeout: nil, resolver: nil, http_factory: nil)
      @url = url.to_s
      @payload = payload
      @headers = headers || {}
      @timeout = Integer(timeout || RailsNexus.configuration.webhook_timeout || 5)
      @resolver = resolver || method(:resolve_addresses)
      @http_factory = http_factory || ->(host, port) { Net::HTTP.new(host, port) }
    end

    def deliver
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      uri, address = validated_destination
      http = build_http(uri, address)
      response = http.request(build_request(uri))
      status = response.code.to_i
      duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at

      if status.between?(300, 399)
        return failure("Webhook redirects are not allowed", status_code: response.code, duration: duration)
      end

      {
        success: status.between?(200, 299),
        status_code: response.code,
        body: response.body.to_s.truncate(500),
        duration: duration.round(3),
        error: status.between?(200, 299) ? nil : "Webhook returned HTTP #{status}"
      }
    rescue ValidationError => error
      failure(error.message)
    rescue StandardError
      failure("Webhook delivery failed")
    end

    private

    def validated_destination
      uri = URI.parse(@url)
      allowed_schemes = ["https"]
      if Rails.env.development? && RailsNexus.configuration.webhook_allow_http_in_development
        allowed_schemes << "http"
      end

      raise ValidationError, "Webhook URL must use HTTPS" unless allowed_schemes.include?(uri.scheme)
      raise ValidationError, "Webhook URL must include a hostname" if uri.host.blank?
      raise ValidationError, "Webhook URL credentials are not allowed" if uri.userinfo.present?
      validate_host_policy!(uri.host)

      addresses = Array(@resolver.call(uri.host)).map { |address| IPAddr.new(address.to_s) }.uniq
      raise ValidationError, "Webhook host could not be resolved" if addresses.empty?
      raise ValidationError, "Webhook destination is not publicly routable" if addresses.any? { |address| blocked_address?(address) }

      [uri, addresses.first.to_s]
    rescue URI::InvalidURIError, IPAddr::InvalidAddressError
      raise ValidationError, "Webhook URL is invalid"
    rescue SocketError
      raise ValidationError, "Webhook host could not be resolved"
    end

    def resolve_addresses(host)
      Addrinfo.getaddrinfo(host, nil, :UNSPEC, :STREAM).map(&:ip_address)
    end

    def blocked_address?(address)
      BLOCKED_NETWORKS.any? { |network| network.include?(address) }
    end

    def validate_host_policy!(host)
      denied = Array(RailsNexus.configuration.webhook_denied_hosts)
      allowed = Array(RailsNexus.configuration.webhook_allowed_hosts)

      raise ValidationError, "Webhook hostname is denied" if denied.any? { |pattern| host_matches?(host, pattern) }
      if allowed.any? && allowed.none? { |pattern| host_matches?(host, pattern) }
        raise ValidationError, "Webhook hostname is not allowed"
      end
    end

    def host_matches?(host, pattern)
      candidate = pattern.to_s.downcase
      actual = host.to_s.downcase
      return actual.end_with?(candidate.delete_prefix("*")) if candidate.start_with?("*.")
      actual == candidate
    end

    def build_http(uri, address)
      http = @http_factory.call(uri.host, uri.port)
      http.ipaddr = address
      http.use_ssl = uri.scheme == "https"
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER if http.use_ssl?
      http.open_timeout = @timeout
      http.read_timeout = @timeout
      http
    end

    def build_request(uri)
      request = Net::HTTP::Post.new(uri.request_uri)
      request["Host"] = uri.port == uri.default_port ? uri.host : "#{uri.host}:#{uri.port}"
      request["Content-Type"] = "application/json"
      @headers.each do |name, value|
        validate_header!(name, value)
        request[name.to_s] = value.to_s
      end
      request.body = @payload.to_json
      request
    end

    def validate_header!(name, value)
      if name.to_s.match?(/[\r\n]/) || value.to_s.match?(/[\r\n]/)
        raise ValidationError, "Webhook header is invalid"
      end
    end

    def failure(message, status_code: nil, duration: nil)
      { success: false, error: message, status_code: status_code, duration: duration&.round(3) }
    end
  end
end
