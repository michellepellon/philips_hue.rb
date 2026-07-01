# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PhilipsHue::Light do
  let(:white_bulb) do
    {
      'id' => '3a5f9b2c-uuid',
      'id_v1' => '/lights/3',
      'type' => 'light',
      'metadata' => { 'name' => 'Office Lamp' },
      'on' => { 'on' => true },
      'dimming' => { 'brightness' => 64.0, 'min_dim_level' => 0.2 }
    }
  end

  let(:color_bulb) do
    white_bulb.merge(
      'color_temperature' => { 'mirek' => 366, 'mirek_valid' => true },
      'color' => { 'xy' => { 'x' => 0.4573, 'y' => 0.41 }, 'gamut_type' => 'C' }
    )
  end

  describe '.from_api' do
    subject(:light) { described_class.from_api(white_bulb) }

    it 'maps identifiers' do
      expect(light.id).to eq('3a5f9b2c-uuid')
      expect(light.id_v1).to eq('/lights/3')
    end

    it 'reads the name out of metadata' do
      expect(light.name).to eq('Office Lamp')
    end

    it 'reads on/off state' do
      expect(light.on).to be(true)
      expect(light.on?).to be(true)
    end

    it 'reads dimming as a 0-100 float percentage' do
      expect(light.brightness).to eq(64.0)
      expect(light.min_dim_level).to eq(0.2)
    end

    it 'reports no colour capabilities for a white-only bulb' do
      expect(light.supports_color?).to be(false)
      expect(light.supports_color_temperature?).to be(false)
      expect(light.color_temp_mirek).to be_nil
      expect(light.color_xy).to be_nil
    end
  end

  describe '.from_api with colour services' do
    subject(:light) { described_class.from_api(color_bulb) }

    it 'detects colour-temperature support and reads mirek' do
      expect(light.supports_color_temperature?).to be(true)
      expect(light.color_temp_mirek).to eq(366)
    end

    it 'detects colour support and reads the xy pair' do
      expect(light.supports_color?).to be(true)
      expect(light.color_xy).to eq([0.4573, 0.41])
    end
  end

  describe 'immutability and equality' do
    it 'produces frozen, value-equal instances' do
      a = described_class.from_api(white_bulb)
      b = described_class.from_api(white_bulb)
      expect(a).to be_frozen
      expect(a).to eq(b)
    end
  end

  describe 'pattern matching' do
    it 'deconstructs by keys' do
      light = described_class.from_api(white_bulb)
      result =
        case light
        in { on: true, brightness: b }
          "on@#{b}"
        else
          'no match'
        end
      expect(result).to eq('on@64.0')
    end
  end

  describe '.new' do
    it 'accepts keyword arguments directly' do
      light = described_class.new(
        id: 'x', id_v1: nil, name: 'Test', on: false, brightness: 10.0,
        min_dim_level: nil, color_temp_mirek: nil, color_xy: nil,
        supports_color_temperature: false, supports_color: false
      )
      expect(light.name).to eq('Test')
      expect(light.on?).to be(false)
    end
  end
end
