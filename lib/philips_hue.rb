# frozen_string_literal: true

require_relative 'philips_hue/version'
require_relative 'philips_hue/parseable'
require_relative 'philips_hue/bridge_info'
require_relative 'philips_hue/app_key'
require_relative 'philips_hue/light'
require_relative 'philips_hue/hue_event'
require_relative 'philips_hue/rate_limiter'
require_relative 'philips_hue/connection'
require_relative 'philips_hue/discovery'
require_relative 'philips_hue/event_stream'
require_relative 'philips_hue/client'

# The PhilipsHue module provides functionality for interacting with the local
# Philips Hue CLIP API v2.
#
# All control flows through a Hue Bridge on the same LAN; the Zigbee bulbs do
# not expose an API directly. The Bridge serves an HTTPS-only REST API behind a
# self-signed certificate, so TLS handling is configurable (see {Client}).
#
# @example Discover, pair, and control a light
#   bridge = PhilipsHue.discover_bridges.first
#   key    = PhilipsHue.create_app_key(bridge.internal_ip_address, device_type: 'demo#cli')
#
#   hue = PhilipsHue.new(bridge_ip: bridge.internal_ip_address, app_key: key.username)
#   light = hue.get_lights.first
#   hue.set_light(light.id, on: true, brightness: 75)
#
# @example React to state changes in real time
#   hue.events do |event|
#     puts "#{event.type}: #{event.data.inspect}"
#   end
#
# @example Using pattern matching (Ruby 4.0+)
#   hue.get_lights.each do |light|
#     case light
#     in { on: true, brightness: }
#       puts "#{light.name} is on at #{brightness}%"
#     in { on: false }
#       puts "#{light.name} is off"
#     end
#   end
module PhilipsHue
  # Base error class for PhilipsHue-specific exceptions.
  #
  # All gem errors inherit from this class, allowing you to rescue every
  # gem-related error with a single rescue clause.
  #
  # @example Rescuing all PhilipsHue errors
  #   begin
  #     hue.get_lights
  #   rescue PhilipsHue::Error => e
  #     warn "Hue error: #{e.message}"
  #   end
  class Error < StandardError; end

  # Raised when the Bridge reports a problem in the `errors` array of a CLIP v2
  # response (these arrive even on HTTP 200, so they must always be inspected).
  #
  # @example Handling a Bridge-reported error
  #   begin
  #     hue.set_light('bad-uuid', on: true)
  #   rescue PhilipsHue::HueError => e
  #     warn "Bridge error (type #{e.error_type}): #{e.description}"
  #   end
  class HueError < Error
    # @return [Integer, nil] HTTP status code, when the failure was HTTP-level
    attr_reader :status

    # @return [Integer, nil] Hue error `type`, when the Bridge supplies one
    attr_reader :error_type

    # @return [String, nil] human-readable `description` from the Bridge
    attr_reader :description

    # Initialize a new Bridge error.
    #
    # @param message [String] human-readable error description
    # @param status [Integer, nil] HTTP status code
    # @param error_type [Integer, nil] Hue error type code
    # @param description [String, nil] description string from the Bridge
    def initialize(message, status: nil, error_type: nil, description: nil)
      @status = status
      @error_type = error_type
      @description = description
      super(message)
    end
  end

  # Raised during pairing while the physical link button has not yet been
  # pressed (Bridge error type 101). {Client.create_app_key} swallows this and
  # keeps polling, so callers rarely see it directly.
  class LinkButtonNotPressedError < HueError; end

  # Raised when the network transport fails: connection refused, TLS handshake
  # failure, timeout, or a dropped event-stream connection.
  #
  # @example
  #   begin
  #     hue.get_lights
  #   rescue PhilipsHue::ConnectionError => e
  #     warn "Could not reach the Bridge: #{e.message}"
  #   end
  class ConnectionError < Error; end

  # Raised when a response body cannot be parsed as the expected JSON shape.
  class ParseError < Error; end

  # Raised when Bridge discovery fails on every configured strategy.
  class DiscoveryError < Error; end

  class << self
    # Factory method to create a new {Client}.
    #
    # Accepts the same keyword arguments as {Client#initialize}.
    #
    # @return [PhilipsHue::Client] a configured client instance
    #
    # @example
    #   hue = PhilipsHue.new(bridge_ip: '192.168.1.42', app_key: 'abc123')
    def new(...)
      Client.new(...)
    end

    # Discover Hue Bridges on the local network.
    #
    # @see Discovery.discover
    # @return [Array<PhilipsHue::BridgeInfo>] discovered bridges
    def discover_bridges(...)
      Discovery.discover(...)
    end

    # Pair with a Bridge and obtain an application key.
    #
    # @see Client.create_app_key
    # @return [PhilipsHue::AppKey] the generated application key
    def create_app_key(...)
      Client.create_app_key(...)
    end
  end
end
