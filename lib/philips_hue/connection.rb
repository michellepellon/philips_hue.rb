# frozen_string_literal: true

require 'net/http'
require 'openssl'

module PhilipsHue
  # Builds configured Net::HTTP connections to the Bridge.
  #
  # This is the single source of truth for TLS handling, shared by {Client} and
  # {EventStream}. The Bridge serves an HTTPS-only API behind a self-signed
  # certificate whose common name is the Bridge ID (not its IP), which makes
  # verification awkward:
  #
  # - **Disabled (default):** verification is turned off and a one-time warning
  #   is emitted. Appropriate for local/dev use against a trusted LAN.
  # - **Strict:** pass a CA bundle path. The connection then verifies against
  #   that bundle and, when a `bridge_id` is supplied, connects to the IP while
  #   presenting the Bridge ID as the TLS hostname so the certificate's common
  #   name validates.
  module Connection
    module_function

    # Default HTTPS port the Bridge listens on.
    # @return [Integer]
    DEFAULT_PORT = 443

    # Build a configured (but not yet started) Net::HTTP instance.
    #
    # @param ip [String] the Bridge LAN IP address to connect to
    # @param port [Integer] the HTTPS port (default 443)
    # @param verify_tls [Boolean, String] false to disable verification, true to
    #   verify against the system store, or a path to a CA bundle for strict mode
    # @param ca_bundle [String, nil] explicit CA bundle path (overrides a string
    #   passed via verify_tls only when that string is absent)
    # @param bridge_id [String, nil] the 16-hex-char Bridge ID, used as the TLS
    #   hostname in strict mode so the self-signed cert's CN validates
    # @param open_timeout [Integer, Float] connection-open timeout in seconds
    # @param read_timeout [Integer, Float, nil] read timeout in seconds; nil
    #   disables it (useful for the long-lived event stream)
    # @return [Net::HTTP] a configured Net::HTTP instance
    def build_http(ip:, port: DEFAULT_PORT, verify_tls: false, ca_bundle: nil,
                   bridge_id: nil, open_timeout: 10, read_timeout: 10)
      verify, ca = normalize_tls(verify_tls, ca_bundle)
      warn_insecure_once unless verify

      host = verify && bridge_id ? bridge_id : ip
      http = Net::HTTP.new(host, port)
      http.use_ssl = true
      http.ipaddr = ip unless host == ip
      http.open_timeout = open_timeout
      http.read_timeout = read_timeout unless read_timeout.nil?
      configure_tls(http, verify, ca)
      http
    end

    # Normalize the dual-purpose `verify_tls` option into a boolean plus an
    # optional CA bundle path.
    #
    # @param verify_tls [Boolean, String] the raw option value
    # @param ca_bundle [String, nil] an explicit CA bundle path
    # @return [Array(Boolean, String|nil)] [verify?, ca_bundle]
    def normalize_tls(verify_tls, ca_bundle)
      return [true, ca_bundle || verify_tls] if verify_tls.is_a?(String)

      [verify_tls ? true : false, ca_bundle]
    end

    # Apply the verification mode and CA bundle to an HTTP instance.
    #
    # @param http [Net::HTTP] the connection to configure
    # @param verify [Boolean] whether to verify the peer certificate
    # @param ca_bundle [String, nil] CA bundle path for strict verification
    # @return [void]
    def configure_tls(http, verify, ca_bundle)
      if verify
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        http.ca_file = ca_bundle if ca_bundle
      else
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end
    end

    # Emit a single process-wide warning when TLS verification is disabled.
    #
    # @return [void]
    def warn_insecure_once
      return if @warned

      @warned = true
      warn('[philips_hue] TLS verification is disabled. This is acceptable for ' \
           'local/dev use; pass a CA bundle path via verify_tls for strict mode.')
    end

    # Reset the one-time insecure-warning latch. Intended for tests.
    #
    # @return [void]
    # @api private
    def reset_warning!
      @warned = false
    end
  end
end
