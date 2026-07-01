# frozen_string_literal: true

module PhilipsHue
  # The credentials returned by the Bridge when pairing succeeds.
  #
  # The `username` is reused as the v2 `hue-application-key` for all subsequent
  # requests. The `clientkey` is only needed for the Entertainment streaming
  # API; it is stored here but otherwise unused by this client.
  #
  # AppKey is an immutable value object built on Ruby's Data class.
  #
  # @example
  #   key = PhilipsHue.create_app_key('192.168.1.42', device_type: 'demo#cli')
  #   hue = PhilipsHue.new(bridge_ip: '192.168.1.42', app_key: key.username)
  class AppKey < Data.define(:username, :clientkey)
    # Create an AppKey from a pairing success payload.
    #
    # @param attributes [Hash] the `success` object from the registration response
    # @option attributes [String] "username" the application key
    # @option attributes [String] "clientkey" the Entertainment client key
    # @return [AppKey] new immutable AppKey instance
    def self.from_api(attributes)
      new(username: attributes['username'], clientkey: attributes['clientkey'])
    end

    # The application key (alias for {#username}), used as the
    # `hue-application-key` header value.
    #
    # @return [String]
    def app_key = username
  end
end
