# frozen_string_literal: true

require 'net/http'
require 'json'
require 'openssl'

module PhilipsHue
  # Subscribes to the Bridge's Server-Sent Events stream and yields {HueEvent}s.
  #
  # The Bridge exposes a long-lived +GET /eventstream/clip/v2+ endpoint that
  # pushes state changes as SSE frames. This class manages the connection
  # lifecycle: it streams the body incrementally, reassembles SSE frames across
  # network chunks, and transparently reconnects with exponential backoff when
  # the connection drops (which it does routinely). Call {#stop} to break out of
  # the loop.
  #
  # @example Print every update event until interrupted
  #   stream = PhilipsHue::EventStream.new(ip: '192.168.1.42', app_key: key)
  #   stream.each do |event|
  #     puts "#{event.type}: #{event.data.inspect}"
  #   end
  class EventStream
    # The CLIP v2 event-stream path.
    # @return [String]
    STREAM_PATH = '/eventstream/clip/v2'

    # Transport errors that indicate a dropped connection worth retrying.
    # @return [Array<Class>]
    TRANSIENT_ERRORS = [
      Net::OpenTimeout, Net::ReadTimeout, IOError, EOFError,
      SocketError, SystemCallError, OpenSSL::SSL::SSLError
    ].freeze

    # Initialize a new event stream.
    #
    # @param ip [String] the Bridge LAN IP address
    # @param app_key [String] the application key (sent as +hue-application-key+)
    # @param port [Integer] the HTTPS port (default 443)
    # @param verify_tls [Boolean, String] TLS verification mode (see {Connection})
    # @param ca_bundle [String, nil] CA bundle path for strict verification
    # @param bridge_id [String, nil] Bridge ID used as the TLS hostname in strict mode
    # @param open_timeout [Integer, Float] connection-open timeout in seconds
    # @param read_timeout [Integer, Float] read timeout for the long-lived stream
    # @param backoff_base [Float] initial reconnect backoff in seconds
    # @param max_backoff [Float] maximum reconnect backoff in seconds
    # @param sleeper [#call, nil] callable invoked with a duration to wait;
    #   injectable so tests never really sleep
    def initialize(ip:, app_key:, port: 443, verify_tls: false, ca_bundle: nil,
                   bridge_id: nil, open_timeout: 10, read_timeout: 90,
                   backoff_base: 1.0, max_backoff: 30.0, sleeper: nil)
      @ip = ip
      @app_key = app_key
      @port = port
      @verify_tls = verify_tls
      @ca_bundle = ca_bundle
      @bridge_id = bridge_id
      @open_timeout = open_timeout
      @read_timeout = read_timeout
      @backoff_base = backoff_base
      @max_backoff = max_backoff
      @sleeper = sleeper || ->(seconds) { sleep(seconds) }
      @buffer = +''
      @stopped = false
    end

    # Stream events, yielding each {HueEvent} as it arrives.
    #
    # Loops until {#stop} is called, reconnecting with exponential backoff on
    # any transient transport failure. Returns an Enumerator when called without
    # a block.
    #
    # @yieldparam event [PhilipsHue::HueEvent] a decoded event
    # @return [Enumerator, nil] an Enumerator when no block is given, else nil
    #
    # @example
    #   stream.each { |event| puts event.type }
    def each(&)
      return enum_for(:each) unless block_given?

      @stopped = false
      backoff = @backoff_base
      until @stopped
        delivered = false
        begin
          delivered = stream_once(&)
        rescue *TRANSIENT_ERRORS
          nil
        end
        break if @stopped

        # Back off before every reconnect (graceful EOF or error alike) so a
        # Bridge that keeps closing the stream can't be hammered; a connection
        # that actually delivered data resets the backoff magnitude.
        backoff = @backoff_base if delivered
        @sleeper.call(backoff)
        backoff = [backoff * 2, @max_backoff].min
      end
      nil
    end

    # Signal the {#each} loop to exit after the current read completes.
    #
    # @return [void]
    def stop
      @stopped = true
    end

    # Feed a raw stream chunk into the SSE parser, yielding a {HueEvent} for each
    # object in each complete event's JSON payload.
    #
    # Maintains an internal buffer across calls so events split across chunks are
    # reassembled. Pure and socket-free for unit testing.
    #
    # @param chunk [String] a chunk of the raw response body
    # @yieldparam event [PhilipsHue::HueEvent] a decoded event
    # @return [void]
    def feed(chunk, &)
      @buffer << chunk.gsub("\r\n", "\n")
      while (index = @buffer.index("\n\n"))
        raw = @buffer.slice!(0, index + 2)
        process_event(raw, &)
      end
    end

    private

    # Parse one complete SSE frame and yield a {HueEvent} per payload object.
    #
    # @param raw [String] the frame text (up to and including its blank line)
    # @yieldparam event [PhilipsHue::HueEvent]
    # @return [void]
    def process_event(raw)
      data_lines = []
      raw.each_line(chomp: true) do |line|
        next if line.empty? || line.start_with?(':')

        field, _, value = line.partition(':')
        data_lines << value.sub(/\A /, '') if field == 'data'
      end
      return if data_lines.empty?

      Array(JSON.parse(data_lines.join("\n"))).each { |object| yield HueEvent.from_api(object) }
    rescue JSON::ParserError
      nil
    end

    # Open one connection and stream it to completion, yielding events.
    #
    # @yieldparam event [PhilipsHue::HueEvent]
    # @return [Boolean] whether any event was delivered on this connection
    def stream_once(&)
      @buffer = +''
      http = build_connection
      http.start do |conn|
        conn.request(build_request) do |response|
          return consume_stream(response, &)
        end
      end
      false
    end

    # Read a streaming response body, feeding chunks to the parser.
    #
    # @param response [Net::HTTPResponse] the open response
    # @yieldparam event [PhilipsHue::HueEvent]
    # @return [Boolean] whether any event was delivered
    def consume_stream(response)
      delivered = false
      response.read_body do |chunk|
        feed(chunk) do |event|
          delivered = true
          yield event
        end
        break if @stopped
      end
      delivered
    end

    # Build the configured (unstarted) connection for the stream.
    #
    # @return [Net::HTTP]
    def build_connection
      Connection.build_http(
        ip: @ip, port: @port, verify_tls: @verify_tls, ca_bundle: @ca_bundle,
        bridge_id: @bridge_id, open_timeout: @open_timeout, read_timeout: @read_timeout
      )
    end

    # Build the SSE GET request.
    #
    # @return [Net::HTTP::Get]
    def build_request
      request = Net::HTTP::Get.new(STREAM_PATH)
      request['hue-application-key'] = @app_key
      request['Accept'] = 'text/event-stream'
      request
    end
  end
end
