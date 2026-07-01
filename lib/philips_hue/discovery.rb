# frozen_string_literal: true

require 'net/http'
require 'json'
require 'openssl'
require 'uri'
require 'resolv'
require 'socket'

module PhilipsHue
  # Locates Hue Bridges on the network.
  #
  # Two independent strategies are offered. Cloud discovery asks the
  # vendor-hosted endpoint which Bridges last phoned home from your public IP;
  # it is fast and reliable but requires outbound internet access. mDNS
  # discovery sends a multicast query on the LAN and is fully local but can be
  # blocked by some routers/VLANs. {discover} tries one and falls back to the
  # other.
  #
  # @example Discover with the default preference (mDNS first, then cloud)
  #   bridges = PhilipsHue::Discovery.discover
  #
  # @example Force cloud discovery first
  #   bridges = PhilipsHue::Discovery.discover(prefer: :cloud)
  module Discovery
    module_function

    # The vendor-hosted discovery endpoint.
    # @return [String]
    CLOUD_URL = 'https://discovery.meethue.com'

    # The DNS-SD service name advertised by Hue Bridges.
    # @return [String]
    SERVICE = '_hue._tcp.local'

    # The IPv4 multicast DNS group address.
    # @return [String]
    MDNS_ADDRESS = '224.0.0.251'

    # The multicast DNS port.
    # @return [Integer]
    MDNS_PORT = 5353

    # Maximum mDNS datagram size to read.
    # @return [Integer]
    MAX_PACKET = 9000

    # Discover Bridges, trying the preferred strategy first and falling back to
    # the other if it yields nothing (or raises).
    #
    # @param prefer [Symbol] either +:mdns+ or +:cloud+ (the strategy to try
    #   first; the other is used as a fallback)
    # @param timeout [Integer, Float] per-strategy timeout in seconds
    # @return [Array<PhilipsHue::BridgeInfo>] discovered bridges; empty if both
    #   strategies come up empty
    #
    # @example
    #   PhilipsHue::Discovery.discover(prefer: :cloud, timeout: 3)
    def discover(prefer: :mdns, timeout: 5)
      order = prefer == :cloud ? %i[cloud mdns] : %i[mdns cloud]
      order.each do |strategy|
        result = send(strategy, timeout: timeout)
        return result unless result.empty?
      rescue StandardError
        next
      end
      []
    end

    # Discover Bridges through the vendor-hosted cloud endpoint.
    #
    # @param timeout [Integer, Float] connection and read timeout in seconds
    # @return [Array<PhilipsHue::BridgeInfo>] discovered bridges
    # @raise [ConnectionError] if the endpoint cannot be reached
    # @raise [ParseError] if the response is not valid JSON
    #
    # @example
    #   PhilipsHue::Discovery.cloud
    def cloud(timeout: 5)
      parse_cloud(fetch_cloud(timeout))
    end

    # Discover Bridges on the local network via multicast DNS.
    #
    # This is best-effort: any socket error or an empty result yields an empty
    # array rather than raising.
    #
    # @param timeout [Integer, Float] how long to listen for responses, seconds
    # @return [Array<PhilipsHue::BridgeInfo>] discovered bridges (possibly empty)
    #
    # @example
    #   PhilipsHue::Discovery.mdns(timeout: 3)
    def mdns(timeout: 5)
      socket = open_mdns_socket
      send_query(socket)
      messages = collect_responses(socket, timeout)
      hashes = messages.flat_map { |message| parse_message(message) }
      dedupe(hashes).map { |attributes| BridgeInfo.from_api(attributes) }
    rescue StandardError
      []
    ensure
      socket&.close
    end

    # Extract bridge attribute hashes from a decoded mDNS response message.
    #
    # Pure and socket-free so the framing/decoding logic can be unit-tested by
    # constructing, encoding, and decoding a {Resolv::DNS::Message}.
    #
    # @param message [Resolv::DNS::Message] a decoded response
    # @return [Array<Hash{String=>Object}>] string-keyed hashes suitable for
    #   {BridgeInfo.from_api} (one per A record found)
    def parse_message(message)
      records = (message.answer + message.additional).map { |(_name, _ttl, data)| data }
      bridge_id = bridge_id_from_records(records)
      records.grep(Resolv::DNS::Resource::IN::A).map(&:address).map(&:to_s).uniq.map do |ip|
        { 'internalipaddress' => ip, 'id' => bridge_id, 'port' => BridgeInfo::DEFAULT_PORT }
      end
    end

    # Determine the Bridge ID from a message's records: prefer a TXT
    # +bridgeid=...+ value, falling back to the PTR instance name.
    #
    # @param records [Array] the message's decoded resource records
    # @return [String, nil] the bridge id, or nil if undetermined
    def bridge_id_from_records(records)
      txt = records.grep(Resolv::DNS::Resource::IN::TXT).flat_map(&:strings)
      ptr = records.grep(Resolv::DNS::Resource::IN::PTR).first
      bridge_id_from_txt(txt) || id_from_instance(ptr&.name&.to_s)
    end

    # Fetch the raw cloud-discovery response body.
    #
    # @param timeout [Integer, Float] connection and read timeout
    # @return [String] the response body
    # @raise [ConnectionError] on any transport failure
    def fetch_cloud(timeout)
      uri = URI(CLOUD_URL)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      http.open_timeout = timeout
      http.read_timeout = timeout
      http.request(Net::HTTP::Get.new(uri)).body
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, OpenSSL::SSL::SSLError => e
      raise ConnectionError, "Cloud discovery failed: #{e.message}"
    end

    # Parse a cloud-discovery body into BridgeInfo objects.
    #
    # @param body [String] the JSON array body
    # @return [Array<PhilipsHue::BridgeInfo>]
    # @raise [ParseError] if the body is not valid JSON
    def parse_cloud(body)
      Array(JSON.parse(body)).map { |entry| BridgeInfo.from_api(entry) }
    rescue JSON::ParserError => e
      raise ParseError, "Invalid cloud discovery response: #{e.message}"
    end

    # Open a UDP socket suitable for sending the multicast query.
    #
    # @return [UDPSocket]
    def open_mdns_socket
      socket = UDPSocket.new
      socket.setsockopt(Socket::IPPROTO_IP, Socket::IP_MULTICAST_TTL, 1)
      socket
    end

    # Send a PTR query for the Hue service to the multicast group.
    #
    # @param socket [UDPSocket] the socket to send on
    # @return [void]
    def send_query(socket)
      query = Resolv::DNS::Message.new(0)
      query.add_question(SERVICE, Resolv::DNS::Resource::IN::PTR)
      socket.send(query.encode, 0, MDNS_ADDRESS, MDNS_PORT)
    end

    # Collect and decode responses until the timeout elapses.
    #
    # @param socket [UDPSocket] the socket to read from
    # @param timeout [Integer, Float] listen window in seconds
    # @return [Array<Resolv::DNS::Message>] decoded responses
    def collect_responses(socket, timeout)
      deadline = monotonic + timeout
      messages = []
      loop do
        remaining = deadline - monotonic
        break if remaining <= 0
        break unless socket.wait_readable(remaining)

        data, = socket.recvfrom(MAX_PACKET)
        messages << Resolv::DNS::Message.decode(data)
      end
      messages
    end

    # Pull the Bridge ID out of a TXT record's strings (the +bridgeid=...+ key).
    #
    # @param strings [Array<String>] the TXT record strings
    # @return [String, nil] the bridge id, or nil if absent
    def bridge_id_from_txt(strings)
      strings.each do |string|
        match = string.match(/\Abridgeid=(.+)\z/i)
        return match[1] if match
      end
      nil
    end

    # Derive a Bridge ID from a service instance name by stripping the service
    # suffix.
    #
    # @param name [String, nil] the instance name (e.g. from a PTR record)
    # @return [String, nil] the leading label, or nil if unavailable
    def id_from_instance(name)
      return nil unless name

      label = name.sub(/\.?#{Regexp.escape(SERVICE)}\.?\z/i, '')
      label.empty? ? nil : label
    end

    # Drop duplicate bridge hashes that share an IP address.
    #
    # @param hashes [Array<Hash>] candidate bridge attribute hashes
    # @return [Array<Hash>] de-duplicated hashes
    def dedupe(hashes)
      hashes.uniq { |hash| hash['internalipaddress'] }
    end

    # Current monotonic clock reading in seconds.
    #
    # @return [Float]
    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
