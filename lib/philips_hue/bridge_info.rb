# frozen_string_literal: true

module PhilipsHue
  # Represents a Hue Bridge located via discovery.
  #
  # BridgeInfo is an immutable value object built on Ruby's Data class,
  # providing value-based equality and frozen instances.
  #
  # @example Basic usage
  #   bridge = PhilipsHue.discover_bridges.first
  #   puts "#{bridge.id} @ #{bridge.internal_ip_address}:#{bridge.port}"
  #
  # @example Using pattern matching
  #   case bridge
  #   in { internal_ip_address: ip }
  #     PhilipsHue.new(bridge_ip: ip, app_key: key)
  #   end
  class BridgeInfo < Data.define(:id, :internal_ip_address, :port)
    # Default HTTPS port the Bridge listens on.
    # @return [Integer]
    DEFAULT_PORT = 443

    # Create a BridgeInfo from discovery payload attributes.
    #
    # Handles both the cloud discovery shape (`internalipaddress`) and the
    # normalized mDNS shape (`internal_ip_address` / `ip`).
    #
    # @param attributes [Hash] bridge attributes from a discovery source
    # @option attributes [String] "id" the 16-hex-char Bridge ID
    # @option attributes [String] "internalipaddress" LAN IP address
    # @option attributes [Integer] "port" HTTPS port (defaults to 443)
    # @return [BridgeInfo] new immutable BridgeInfo instance
    def self.from_api(attributes)
      ip = attributes['internalipaddress'] || attributes['internal_ip_address'] || attributes['ip']
      new(
        id: attributes['id'],
        internal_ip_address: ip,
        port: attributes['port'] || DEFAULT_PORT
      )
    end
  end
end
