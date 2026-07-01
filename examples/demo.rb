#!/usr/bin/env ruby
# frozen_string_literal: true

# Connect to a paired Bridge, list lights, toggle one, and stream live events.
#
# Requires the environment variables produced by examples/pair.rb:
#   export HUE_BRIDGE_IP=192.168.1.42
#   export HUE_APP_KEY=your-application-key
#
# Usage:
#   ruby examples/demo.rb
#
# Once it is streaming, change the light from the Hue app and watch the events
# print. Press Ctrl-C to stop.

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'json'
require 'philips_hue'

hue = PhilipsHue::Client.from_env

puts 'Lights on this Bridge:'
lights = hue.get_lights
lights.each do |light|
  state = light.on? ? "on @ #{light.brightness}%" : 'off'
  puts "  - #{light.name} (#{state})  id=#{light.id}"
end
abort 'No lights found.' if lights.empty?

target = lights.first
puts
puts "Turning '#{target.name}' on at 75%..."
hue.set_light(target.id, on: true, brightness: 75)
sleep 2

puts "Turning '#{target.name}' off..."
hue.set_light(target.id, on: false)

puts
puts 'Streaming events. Change a light from the Hue app to see updates.'
puts 'Press Ctrl-C to stop.'

begin
  hue.events do |event|
    next unless event.update?

    event.data.each do |resource|
      puts "[#{event.type}] #{resource['type']} #{resource['id']}: #{resource.reject { |k, _| %w[id type id_v1 owner].include?(k) }.to_json}"
    end
  end
rescue Interrupt
  puts "\nStopped."
ensure
  hue.close
end
