# frozen_string_literal: true

# This module defines version information in both string and component format,
# allowing programmatic access to individual version numbers (MAJOR, MINOR,
# PATCH) that follow semantic versioning principles.
#
# == Usage Examples
#
#   # Access the complete version string
#   PhilipsHue::VERSION  #=> "0.1.0"
#
#   # Access individual version components
#   PhilipsHue::MAJOR    #=> "0"
#   PhilipsHue::MINOR    #=> "1"
#   PhilipsHue::PATCH    #=> "0"
#
# == Version Components
#
# - MAJOR: Incremented for incompatible API changes
# - MINOR: Incremented for backward-compatible functionality additions
# - PATCH: Incremented for backward-compatible bug fixes
module PhilipsHue
  # The current version of the philips_hue gem
  VERSION = '0.1.0'
  # Version components for programmatic access
  MAJOR, MINOR, PATCH = VERSION.split('.')
end
