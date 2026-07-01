#!/usr/bin/env ruby
# frozen_string_literal: true

# Run once to pair with a Bridge and obtain an application key.
#
# Usage:
#   ruby examples/pair.rb            # discover a Bridge automatically
#   ruby examples/pair.rb 192.168.1.42   # or target a known Bridge IP
#
# Press the physical link button on the Bridge when prompted. The printed
# application key is what you export as HUE_APP_KEY for everyday use.

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'philips_hue'

DEVICE_TYPE = 'philips_hue_ruby#example'

def resolve_bridge_ip(argv)
  return argv.first unless argv.empty?

  puts 'Discovering Hue Bridges on the local network...'
  bridges = PhilipsHue.discover_bridges
  abort 'No Bridges found. Pass the Bridge IP as an argument.' if bridges.empty?

  bridge = bridges.first
  puts "Found Bridge #{bridge.id} at #{bridge.internal_ip_address}"
  bridge.internal_ip_address
end

bridge_ip = resolve_bridge_ip(ARGV)

puts
puts '>>> Press the link button on top of the Bridge now. <<<'
puts 'Waiting up to 30 seconds for the button press...'

begin
  key = PhilipsHue.create_app_key(bridge_ip, device_type: DEVICE_TYPE)
rescue PhilipsHue::Error => e
  abort "Pairing failed: #{e.message}"
end

puts
puts 'Paired! Export these for the demo and your own apps:'
puts
puts "  export HUE_BRIDGE_IP=#{bridge_ip}"
puts "  export HUE_APP_KEY=#{key.username}"
puts
puts "(clientkey, only needed for the Entertainment API: #{key.clientkey})"
