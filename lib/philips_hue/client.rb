# frozen_string_literal: true

require 'net/http'
require 'json'
require 'openssl'

module PhilipsHue
  # The legacy pairing handshake that exchanges a link-button press for an
  # application key.
  #
  # Pairing predates the CLIP v2 API and uses the v1-shaped +POST /api+ endpoint,
  # which returns a JSON array rather than the +{errors, data}+ envelope. It is a
  # stateless, one-shot lifecycle concern, kept separate from the request-bound
  # {Client}.
  module Pairing
    module_function

    # Pair with a Bridge, polling until the link button is pressed.
    #
    # @param bridge_ip [String] the Bridge LAN IP address
    # @param device_type [String] an app identifier, e.g. +'myapp#host'+
    # @param poll_seconds [Integer, Float] how long to wait for the button press
    # @param poll_interval [Integer, Float] delay between poll attempts
    # @param verify_tls [Boolean, String] TLS verification mode (see {Connection})
    # @param ca_bundle [String, nil] CA bundle path for strict verification
    # @param bridge_id [String, nil] Bridge ID for strict-mode TLS hostname
    # @param clock [#call, nil] monotonic clock returning seconds; injectable
    # @param sleeper [#call, nil] callable invoked to wait; injectable
    # @return [PhilipsHue::AppKey] the generated credentials
    # @raise [LinkButtonNotPressedError] if the button is not pressed in time
    # @raise [HueError] on any other Bridge-reported error
    def create_app_key(bridge_ip, device_type:, poll_seconds: 30, poll_interval: 1,
                       verify_tls: false, ca_bundle: nil, bridge_id: nil,
                       clock: nil, sleeper: nil)
      clock ||= -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
      sleeper ||= ->(seconds) { sleep(seconds) }
      http = Connection.build_http(ip: bridge_ip, verify_tls: verify_tls, ca_bundle: ca_bundle, bridge_id: bridge_id)
      deadline = clock.call + poll_seconds

      loop do
        entry = post_registration(http, device_type).first || {}
        return AppKey.from_api(entry['success']) if entry['success']

        handle_error(entry['error'], clock, deadline, sleeper, poll_interval)
      end
    end

    # Issue one registration POST and parse its v1-shaped array response.
    #
    # @param http [Net::HTTP] the configured connection
    # @param device_type [String] the app identifier
    # @return [Array<Hash>] the parsed response array
    # @raise [ParseError] if the body is not valid JSON
    # @raise [ConnectionError] on transport failure
    def post_registration(http, device_type)
      request = Net::HTTP::Post.new('/api')
      request['Content-Type'] = 'application/json'
      request['Accept'] = 'application/json'
      request.body = { devicetype: device_type, generateclientkey: true }.to_json
      Array(JSON.parse(http.start { |conn| conn.request(request) }.body))
    rescue JSON::ParserError => e
      raise ParseError, "Invalid pairing response: #{e.message}"
    rescue Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError, SocketError, SystemCallError => e
      raise ConnectionError, "Pairing request failed: #{e.message}"
    end

    # Act on a pairing error element: keep polling on a link-button error until
    # the deadline, otherwise raise.
    #
    # @param error [Hash, nil] the +error+ object from the response
    # @param clock [#call] monotonic clock
    # @param deadline [Float] the monotonic time after which to give up
    # @param sleeper [#call] wait callable
    # @param poll_interval [Integer, Float] delay between polls
    # @return [void]
    # @raise [LinkButtonNotPressedError, HueError]
    def handle_error(error, clock, deadline, sleeper, poll_interval)
      raise HueError, 'Unexpected pairing response' if error.nil?
      raise pairing_error(error) unless link_button_error?(error)

      if clock.call >= deadline
        raise LinkButtonNotPressedError.new('Link button not pressed in time',
                                            error_type: 101, description: error['description'])
      end
      sleeper.call(poll_interval)
    end

    # @param error [Hash] a pairing error element
    # @return [Boolean] whether it is the "link button not pressed" error
    def link_button_error?(error)
      error['type'] == 101
    end

    # Build a {HueError} from a non-link-button pairing error element.
    #
    # @param error [Hash] a pairing error element
    # @return [HueError]
    def pairing_error(error)
      HueError.new(error['description'] || 'Pairing failed',
                   error_type: error['type'], description: error['description'])
    end
  end

  # The CLIP v2 HTTP transport mixin used by {Client}.
  #
  # Centralizes building a connection, executing a request, mapping transport
  # failures, and surfacing the +errors+ array the Bridge returns even on HTTP
  # 200. Mixed into {Client} as private instance methods; it reads the host's
  # connection configuration from its instance variables.
  module Transport
    private

    # Execute a request, retrying transient transport failures with backoff.
    #
    # @param method [Symbol] +:get+, +:put+, or +:post+
    # @param path [String] the request path
    # @param body [Hash, nil] the JSON body for writes
    # @return [Hash] the parsed response
    # @raise [HueError, ParseError, ConnectionError]
    def request(method, path, body = nil)
      attempts = 0
      begin
        attempts += 1
        perform_request(method, path, body)
      rescue ConnectionError
        raise if attempts >= 3

        @sleeper.call(0.5 * (2**(attempts - 1)))
        retry
      end
    end

    # Perform a single request and map its result/errors.
    #
    # @return [Hash] the parsed response
    def perform_request(method, path, body)
      http = Connection.build_http(
        ip: @bridge_ip, port: @port, verify_tls: @verify_tls, ca_bundle: @ca_bundle,
        bridge_id: @bridge_id, open_timeout: @timeout, read_timeout: @timeout
      )
      parse_response(http.start { |conn| conn.request(build_http_request(method, path, body)) })
    rescue JSON::ParserError => e
      raise ParseError, "Invalid response body: #{e.message}"
    rescue Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError, SocketError, SystemCallError => e
      raise ConnectionError, "Request to #{path} failed: #{e.message}"
    end

    # Build the underlying Net::HTTP request with headers and body.
    #
    # @return [Net::HTTPRequest]
    def build_http_request(method, path, body)
      klass = { get: Net::HTTP::Get, put: Net::HTTP::Put, post: Net::HTTP::Post }.fetch(method)
      request = klass.new(path)
      request['hue-application-key'] = @app_key
      request['Accept'] = 'application/json'
      if body
        request['Content-Type'] = 'application/json'
        request.body = body.to_json
      end
      request
    end

    # Parse a response body and surface Bridge/HTTP errors.
    #
    # @param response [Net::HTTPResponse]
    # @return [Hash] the parsed body
    # @raise [HueError]
    def parse_response(response)
      status = response.code.to_i
      parsed = parse_body(response.body, status)
      check_for_errors(parsed, status)
      raise HueError.new("HTTP #{status}", status: status) unless (200..299).cover?(status)

      parsed
    end

    # Parse a JSON body, mapping a non-2xx parse failure to a HueError.
    #
    # @return [Hash]
    def parse_body(body, status)
      return {} if body.to_s.empty?

      JSON.parse(body)
    rescue JSON::ParserError
      raise HueError.new("HTTP #{status}", status: status) unless (200..299).cover?(status)

      raise
    end

    # Raise a HueError when the v2 +errors+ array is non-empty (even on HTTP 200).
    #
    # @return [void]
    def check_for_errors(parsed, status)
      return unless parsed.is_a?(Hash)

      errors = parsed['errors']
      return unless errors.is_a?(Array) && !errors.empty?

      first = errors.first
      raise HueError.new(first['description'] || 'Bridge error',
                         status: status, error_type: first['type'], description: first['description'])
    end
  end

  # The primary entry point for talking to a paired Hue Bridge.
  #
  # The Client owns HTTP transport to the CLIP v2 API, the resource-control
  # methods (lights and grouped lights), and the live event stream. Writes are
  # throttled through {RateLimiter} instances so the Bridge does not silently
  # drop commands.
  #
  # @example Construct from explicit configuration
  #   hue = PhilipsHue::Client.new(bridge_ip: '192.168.1.42', app_key: 'abc123')
  #   hue.get_lights.each { |light| puts light.name }
  #
  # @example Construct from the environment and clean up afterwards
  #   PhilipsHue::Client.open do |hue|
  #     hue.set_light(id, on: true, brightness: 50)
  #   end
  class Client
    include Transport

    # Default HTTPS port the Bridge listens on.
    # @return [Integer]
    DEFAULT_PORT = 443

    # Initialize a new client.
    #
    # @param bridge_ip [String] the Bridge LAN IP address
    # @param app_key [String] the application key (the +hue-application-key+)
    # @param verify_tls [Boolean, String] TLS verification mode (see {Connection})
    # @param ca_bundle [String, nil] CA bundle path for strict verification
    # @param bridge_id [String, nil] Bridge ID, used as the TLS hostname in strict mode
    # @param timeout [Integer, Float] per-request open/read timeout in seconds
    # @param light_rate [Numeric] sustained writes/second allowed per light
    # @param group_rate [Numeric] sustained writes/second allowed per group
    # @param light_limiter [#acquire, nil] injectable limiter for light writes
    # @param group_limiter [#acquire, nil] injectable limiter for group writes
    # @param sleeper [#call, nil] callable invoked to wait between request
    #   retries; injectable so tests never really sleep
    def initialize(bridge_ip:, app_key:, verify_tls: false, ca_bundle: nil,
                   bridge_id: nil, timeout: 10, light_rate: 10, group_rate: 1,
                   light_limiter: nil, group_limiter: nil, sleeper: nil)
      @bridge_ip = bridge_ip
      @app_key = app_key
      @verify_tls = verify_tls
      @ca_bundle = ca_bundle
      @bridge_id = bridge_id
      @port = DEFAULT_PORT
      @timeout = timeout
      @light_limiter = light_limiter || RateLimiter.new(rate: light_rate)
      @group_limiter = group_limiter || RateLimiter.new(rate: group_rate)
      @sleeper = sleeper || ->(seconds) { sleep(seconds) }
      @stream = nil
    end

    class << self
      # Build a client from environment variables.
      #
      # Reads +HUE_BRIDGE_IP+, +HUE_APP_KEY+, +HUE_VERIFY_TLS+, and
      # +HUE_CA_BUNDLE+. +HUE_VERIFY_TLS+ accepts +'true'+/+'false'+ or, for any
      # other non-empty value, a CA bundle path. Keyword +overrides+ win.
      #
      # @param overrides [Hash] values that take precedence over the environment
      # @return [Client] a configured client
      # @raise [PhilipsHue::Error] if bridge_ip or app_key is missing
      def from_env(**overrides)
        config = {
          bridge_ip: ENV.fetch('HUE_BRIDGE_IP', nil),
          app_key: ENV.fetch('HUE_APP_KEY', nil),
          verify_tls: env_verify_tls,
          ca_bundle: ENV.fetch('HUE_CA_BUNDLE', nil)
        }.merge(overrides)
        if config[:bridge_ip].to_s.empty? || config[:app_key].to_s.empty?
          raise PhilipsHue::Error, 'HUE_BRIDGE_IP and HUE_APP_KEY are required'
        end

        new(**config)
      end

      # Discover Bridges on the network.
      #
      # @param opts [Hash] options forwarded to {Discovery.discover}
      # @return [Array<PhilipsHue::BridgeInfo>]
      def discover_bridges(**)
        Discovery.discover(**)
      end

      # Pair with a Bridge to obtain an application key.
      #
      # @see Pairing.create_app_key
      # @param bridge_ip [String] the Bridge LAN IP address
      # @param opts [Hash] options forwarded to {Pairing.create_app_key}
      # @return [PhilipsHue::AppKey] the generated credentials
      def create_app_key(bridge_ip, **)
        Pairing.create_app_key(bridge_ip, **)
      end

      private

      # Normalize +HUE_VERIFY_TLS+ into a boolean or a CA bundle path.
      #
      # @return [Boolean, String]
      def env_verify_tls
        raw = ENV.fetch('HUE_VERIFY_TLS', nil)
        return false if raw.nil? || raw.empty?

        case raw.downcase
        when 'true'  then true
        when 'false' then false
        else raw
        end
      end
    end

    # Control which instance variables appear in +#inspect+ output, redacting the
    # application key so it is never disclosed through logs or REPL history.
    #
    # @return [Array<Symbol>] the instance variables safe to display
    # @api private
    def instance_variables_to_inspect
      instance_variables - %i[@app_key]
    end

    # Fetch all lights on the Bridge.
    #
    # @return [Array<PhilipsHue::Light>]
    # @raise [HueError] if the Bridge reports an error
    def get_lights # rubocop:disable Naming/AccessorMethodName
      Array(request(:get, '/clip/v2/resource/light')['data']).map { |attrs| Light.from_api(attrs) }
    end

    # Fetch a single light by id.
    #
    # @param id [String] the light's CLIP v2 UUID
    # @return [PhilipsHue::Light]
    # @raise [HueError] if the light is not found or the Bridge reports an error
    def get_light(id)
      data = Array(request(:get, "/clip/v2/resource/light/#{id}")['data'])
      raise HueError.new("Light #{id} not found", status: 404) if data.empty?

      Light.from_api(data.first)
    end

    # Update a light's state.
    #
    # Colour fields are capability-gated: if the bulb does not support the
    # requested colour/colour-temperature service the field is dropped with a
    # warning. If no applicable field remains, no request is made.
    #
    # @param id [String] the light's CLIP v2 UUID
    # @param on [Boolean, nil] power state
    # @param brightness [Numeric, nil] 0-100 percentage (clamped)
    # @param color_temp_mirek [Integer, nil] colour temperature in mirek
    # @param xy [Array(Numeric, Numeric), nil] CIE xy colour coordinate
    # @return [nil]
    # @raise [HueError] if the Bridge reports an error
    def set_light(id, on: nil, brightness: nil, color_temp_mirek: nil, xy: nil) # rubocop:disable Naming/MethodParameterName
      body = base_state(on, brightness)
      apply_color_fields(id, body, color_temp_mirek, xy)
      return nil if body.empty?

      @light_limiter.acquire
      request(:put, "/clip/v2/resource/light/#{id}", body)
      nil
    end

    # Update a grouped light's state (a room or zone).
    #
    # @param grouped_light_id [String] the grouped_light CLIP v2 UUID
    # @param on [Boolean, nil] power state
    # @param brightness [Numeric, nil] 0-100 percentage (clamped)
    # @return [nil]
    # @raise [HueError] if the Bridge reports an error
    def set_group(grouped_light_id, on: nil, brightness: nil)
      body = base_state(on, brightness)
      return nil if body.empty?

      @group_limiter.acquire
      request(:put, "/clip/v2/resource/grouped_light/#{grouped_light_id}", body)
      nil
    end

    # Subscribe to the Bridge event stream.
    #
    # @yieldparam event [PhilipsHue::HueEvent] each event as it arrives
    # @return [Enumerator, nil] an Enumerator when no block is given, else nil
    def events(&block)
      @stream = EventStream.new(
        ip: @bridge_ip, app_key: @app_key, port: @port,
        verify_tls: @verify_tls, ca_bundle: @ca_bundle, bridge_id: @bridge_id
      )
      block ? @stream.each(&block) : @stream.each
    end

    # Stop any active event stream. HTTP is otherwise per-request, so there is
    # nothing else to close.
    #
    # @return [nil]
    def close
      @stream&.stop
      @stream = nil
    end

    # Build a client, optionally yielding it and closing it afterwards.
    #
    # @param kwargs [Hash] keyword arguments forwarded to {#initialize}
    # @yieldparam client [Client] the new client, if a block is given
    # @return [Object, Client] the block's result, or the client when no block
    def self.open(**)
      client = new(**)
      return client unless block_given?

      begin
        yield client
      ensure
        client.close
      end
    end

    private

    # Build the shared on/dimming portion of a write body.
    #
    # @param on [Boolean, nil] power state
    # @param brightness [Numeric, nil] 0-100 percentage
    # @return [Hash] the (possibly empty) body
    def base_state(on, brightness)
      body = {}
      body['on'] = { 'on' => on ? true : false } unless on.nil?
      body['dimming'] = { 'brightness' => brightness.to_f.clamp(0.0, 100.0) } unless brightness.nil?
      body
    end

    # Add capability-gated colour fields to a write body, fetching the light only
    # when a colour field was requested.
    #
    # @param id [String] the light id
    # @param body [Hash] the body to mutate
    # @param color_temp_mirek [Integer, nil] requested colour temperature
    # @param coords [Array, nil] requested xy colour pair
    # @return [void]
    def apply_color_fields(id, body, color_temp_mirek, coords)
      return if color_temp_mirek.nil? && coords.nil?

      light = get_light(id)
      temp = color_temp_mirek && { 'mirek' => color_temp_mirek.to_i }
      xy = coords && { 'xy' => { 'x' => coords[0], 'y' => coords[1] } }
      set_capability(body, light, 'color_temperature', temp, light.supports_color_temperature?)
      set_capability(body, light, 'color', xy, light.supports_color?)
    end

    # Apply a single colour service field, warning and dropping it if the bulb
    # does not support that service.
    #
    # @return [void]
    def set_capability(body, light, key, value, supported)
      return if value.nil?

      if supported
        body[key] = value
      else
        warn("[philips_hue] Light #{light.id} does not support #{key}; ignoring it")
      end
    end
  end
end
