# frozen_string_literal: true

require 'time'

module PhilipsHue
  # Provides parsing utilities shared across model classes.
  #
  # This module contains shared parsing logic used by the value objects so that
  # API-payload handling stays consistent.
  #
  # @example Including in a class
  #   class HueEvent
  #     extend Parseable
  #
  #     def self.from_api(attributes)
  #       new(creationtime: parse_time(attributes['creationtime']))
  #     end
  #   end
  module Parseable
    # Safely parse a timestamp string from an API response.
    #
    # @param time_string [String, nil] ISO8601 timestamp string from the API
    # @return [Time, nil] parsed Time object, or nil if absent/unparseable
    #
    # @example Parsing a valid timestamp
    #   parse_time("2026-01-15T12:30:00Z") #=> 2026-01-15 12:30:00 UTC
    #
    # @example Handling nil or invalid input
    #   parse_time(nil)          #=> nil
    #   parse_time("not a date") #=> nil
    def parse_time(time_string)
      Time.parse(time_string) if time_string
    rescue ArgumentError
      nil
    end
  end
end
