# frozen_string_literal: true

module PhilipsHue
  # Represents an individual Hue light as exposed by the CLIP v2 `light` resource.
  #
  # Light is an immutable value object built on Ruby's Data class, providing
  # value-based equality and frozen instances. It represents a snapshot of the
  # light's state from the API.
  #
  # The capability flags ({#supports_color?} and {#supports_color_temperature?})
  # reflect whether the underlying bulb exposes those services. A Hue White
  # bulb, for example, supports `on` and `dimming` only.
  #
  # @note Brightness uses the v2 scale: a float percentage from 0-100, *not* the
  #   0-254 `bri` value from the v1 API.
  #
  # @example Basic usage
  #   light = hue.get_lights.first
  #   puts "#{light.name}: #{light.on? ? 'on' : 'off'} @ #{light.brightness}%"
  #
  # @example Using pattern matching
  #   case light
  #   in { on: true, brightness: b } if b < 20
  #     puts "#{light.name} is dimly lit"
  #   in { supports_color: true }
  #     puts "#{light.name} can show colour"
  #   end
  class Light < Data.define(
    :id, :id_v1, :name, :on, :brightness, :min_dim_level,
    :color_temp_mirek, :color_xy, :supports_color_temperature, :supports_color
  )
    # Create a Light from a CLIP v2 `light` resource hash.
    #
    # @param attributes [Hash] a single entry from the `data` array of a
    #   `GET /clip/v2/resource/light` response
    # @return [Light] new immutable Light instance
    def self.from_api(attributes)
      dimming = attributes['dimming'] || {}
      color_temp = attributes['color_temperature']
      color = attributes['color']

      new(
        id: attributes['id'],
        id_v1: attributes['id_v1'],
        name: attributes.dig('metadata', 'name'),
        on: attributes.dig('on', 'on'),
        brightness: dimming['brightness'],
        min_dim_level: dimming['min_dim_level'],
        color_temp_mirek: color_temp&.fetch('mirek', nil),
        color_xy: extract_xy(color),
        supports_color_temperature: !color_temp.nil?,
        supports_color: !color.nil?
      )
    end

    # Extract the [x, y] colour coordinate pair from a `color` service hash.
    #
    # @param color [Hash, nil] the `color` service object
    # @return [Array(Float, Float), nil] the xy pair, or nil if unavailable
    def self.extract_xy(color)
      xy = color && color['xy']
      xy && [xy['x'], xy['y']]
    end
    private_class_method :extract_xy

    # @return [Boolean, nil] whether the light is currently on
    def on? = on

    # @return [Boolean] whether the bulb exposes the colour-temperature service
    def supports_color_temperature? = supports_color_temperature

    # @return [Boolean] whether the bulb exposes the colour service
    def supports_color? = supports_color
  end
end
