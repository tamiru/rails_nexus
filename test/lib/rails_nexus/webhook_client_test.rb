# frozen_string_literal: true

require "test_helper"
require "rails_nexus/webhook_client"

class RailsNexus::WebhookClientTest < ActiveSupport::TestCase
  FakeResponse = Struct.new(:code, :body)

  class FakeHTTP
    attr_accessor :ipaddr, :use_ssl, :verify_mode, :open_timeout, :read_timeout
    attr_reader :request_value

    def initialize(response)
      @response = response
    end

    def use_ssl?
      use_ssl
    end

    def request(value)
      @request_value = value
      @response
    end
  end

  setup do
    @original_allowed = RailsNexus.configuration.webhook_allowed_hosts
    @original_denied = RailsNexus.configuration.webhook_denied_hosts
    @original_http = RailsNexus.configuration.webhook_allow_http_in_development
    RailsNexus.configuration.webhook_allowed_hosts = []
    RailsNexus.configuration.webhook_denied_hosts = []
    RailsNexus.configuration.webhook_allow_http_in_development = false
  end

  teardown do
    RailsNexus.configuration.webhook_allowed_hosts = @original_allowed
    RailsNexus.configuration.webhook_denied_hosts = @original_denied
    RailsNexus.configuration.webhook_allow_http_in_development = @original_http
  end

  test "rejects non-HTTPS and credential-bearing URLs" do
    assert_equal "Webhook URL must use HTTPS", deliver("http://example.com", ["93.184.216.34"])[:error]
    assert_equal "Webhook URL credentials are not allowed", deliver("https://user:secret@example.com", ["93.184.216.34"])[:error]
  end

  test "rejects local private metadata and reserved destinations" do
    addresses = [
      "127.0.0.1", "10.0.0.2", "192.168.1.2", "169.254.169.254",
      "::1", "fe80::1", "fc00::1", "224.0.0.1", "203.0.113.10"
    ]

    addresses.each do |address|
      result = deliver("https://example.com/hook", [address])
      assert_equal "Webhook destination is not publicly routable", result[:error], address
    end
  end

  test "rejects mixed DNS answers to prevent rebinding" do
    result = deliver("https://example.com/hook", ["93.184.216.34", "127.0.0.1"])

    assert_equal "Webhook destination is not publicly routable", result[:error]
  end

  test "enforces allowed and denied hostname policies" do
    RailsNexus.configuration.webhook_allowed_hosts = ["*.example.com"]
    RailsNexus.configuration.webhook_denied_hosts = ["blocked.example.com"]

    assert_equal "Webhook hostname is not allowed", deliver("https://other.test/hook", ["8.8.8.8"])[:error]
    assert_equal "Webhook hostname is denied", deliver("https://blocked.example.com/hook", ["8.8.8.8"])[:error]
    assert deliver("https://hooks.example.com/hook", ["8.8.8.8"])[:success]
  end

  test "pins the connection to the validated address and preserves hostname" do
    http = FakeHTTP.new(FakeResponse.new("204", ""))
    client = build_client(
      "https://hooks.example.com:8443/path?token=secret",
      ["8.8.8.8"],
      http: http
    )

    result = client.deliver

    assert result[:success]
    assert_equal "8.8.8.8", http.ipaddr
    assert_equal true, http.use_ssl
    assert_equal OpenSSL::SSL::VERIFY_PEER, http.verify_mode
    assert_equal "hooks.example.com:8443", http.request_value["Host"]
    assert_equal "/path?token=secret", http.request_value.path
  end

  test "rejects redirects without following them" do
    http = FakeHTTP.new(FakeResponse.new("302", "redirect"))

    result = build_client("https://example.com/hook", ["8.8.8.8"], http: http).deliver

    assert_equal "Webhook redirects are not allowed", result[:error]
  end

  test "redacts secrets from logged webhook URLs" do
    assert_equal "https://hooks.example.com/[REDACTED]",
      RailsNexus::WebhookClient.redacted_url("https://user:secret@hooks.example.com/path/token?key=value")
  end

  test "normal notification delivery uses the same destination validation" do
    payload = { event: "exception.logged" }

    assert_difference("RailsNexus::WebhookDelivery.failed.count", 1) do
      RailsNexus::Notifications.send(
        :deliver_webhook,
        "https://127.0.0.1/private/token",
        payload,
        RailsNexus.configuration
      )
    end

    delivery = RailsNexus::WebhookDelivery.recent.first
    assert_equal "https://127.0.0.1/[REDACTED]", delivery.url
    assert_equal "Webhook destination is not publicly routable", delivery.error_message
  end

  private

  def deliver(url, addresses)
    build_client(url, addresses).deliver
  end

  def build_client(url, addresses, http: FakeHTTP.new(FakeResponse.new("200", "ok")))
    RailsNexus::WebhookClient.new(
      url: url,
      payload: { event: "test" },
      resolver: ->(_host) { addresses },
      http_factory: ->(_host, _port) { http }
    )
  end
end
