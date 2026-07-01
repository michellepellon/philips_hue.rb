# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PhilipsHue::BridgeInfo do
  describe '.from_api' do
    it 'maps the cloud discovery shape' do
      info = described_class.from_api(
        'id' => '001788fffe1234ab',
        'internalipaddress' => '192.168.1.42',
        'port' => 443
      )
      expect(info.id).to eq('001788fffe1234ab')
      expect(info.internal_ip_address).to eq('192.168.1.42')
      expect(info.port).to eq(443)
    end

    it 'accepts a normalized mDNS shape and defaults the port' do
      info = described_class.from_api('id' => 'abc', 'ip' => '10.0.0.5')
      expect(info.internal_ip_address).to eq('10.0.0.5')
      expect(info.port).to eq(described_class::DEFAULT_PORT)
    end
  end

  it 'is an immutable value object' do
    a = described_class.new(id: 'a', internal_ip_address: '1.1.1.1', port: 443)
    b = described_class.new(id: 'a', internal_ip_address: '1.1.1.1', port: 443)
    expect(a).to eq(b)
    expect(a).to be_frozen
  end
end
