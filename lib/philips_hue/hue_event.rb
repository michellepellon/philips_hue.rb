# frozen_string_literal: true

module PhilipsHue
  # Represents a single event object from the Bridge push event stream.
  #
  # Each SSE `data:` line carries a JSON array of these event objects. The
  # {#data} member is the array of resource snapshots the event concerns, kept
  # as raw string-keyed hashes so callers can inspect arbitrary resource types.
  #
  # HueEvent is an immutable value object built on Ruby's Data class.
  #
  # @example
  #   hue.events do |event|
  #     next unless event.update?
  #
  #     event.data.each do |resource|
  #       puts "#{resource['type']} #{resource['id']} changed"
  #     end
  #   end
  #
  # @example Using pattern matching
  #   case event
  #   in { type: 'update', data: [{ 'on' => { 'on' => state } }, *] }
  #     puts "light toggled #{state ? 'on' : 'off'}"
  #   end
  class HueEvent < Data.define(:id, :type, :creationtime, :data)
    extend Parseable

    # Recognised event types from the CLIP v2 event stream.
    # @return [Array<String>]
    TYPES = %w[update add delete error].freeze

    # Create a HueEvent from a single event object in the stream payload.
    #
    # @param attributes [Hash] one event object from a `data:` line's JSON array
    # @option attributes [String] "id" event UUID
    # @option attributes [String] "type" one of update/add/delete/error
    # @option attributes [String] "creationtime" ISO8601 timestamp
    # @option attributes [Array<Hash>] "data" affected resource snapshots
    # @return [HueEvent] new immutable HueEvent instance
    def self.from_api(attributes)
      new(
        id: attributes['id'],
        type: attributes['type'],
        creationtime: parse_time(attributes['creationtime']),
        data: attributes['data'] || []
      )
    end

    # @return [Boolean] whether this is an `update` event
    def update? = type == 'update'

    # @return [Boolean] whether this is an `add` event
    def add? = type == 'add'

    # @return [Boolean] whether this is a `delete` event
    def delete? = type == 'delete'

    # @return [Boolean] whether this is an `error` event
    def error? = type == 'error'
  end
end
