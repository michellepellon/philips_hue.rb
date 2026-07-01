# frozen_string_literal: true

require 'spec_helper'
require 'resolv'

RSpec.describe PhilipsHue::Discovery do
  describe '.cloud' do
    let(:payload) do
      JSON.dump(
        [
          { 'id' => '001788fffe1234ab', 'internalipaddress' => '192.168.1.42', 'port' => 443 },
          { 'id' => '001788fffe5678cd', 'internalipaddress' => '192.168.1.43', 'port' => 443 }
        ]
      )
    end

    it 'maps the JSON array into BridgeInfo objects' do
      stub_request(:get, 'https://discovery.meethue.com')
        .to_return(status: 200, body: payload, headers: { 'Content-Type' => 'application/json' })

      bridges = described_class.cloud

      expect(bridges.size).to eq(2)
      expect(bridges.first).to be_a(PhilipsHue::BridgeInfo)
      expect(bridges.first.id).to eq('001788fffe1234ab')
      expect(bridges.first.internal_ip_address).to eq('192.168.1.42')
      expect(bridges.first.port).to eq(443)
    end

    it 'raises ConnectionError on a transport failure' do
      stub_request(:get, 'https://discovery.meethue.com').to_raise(SocketError.new('no route'))

      expect { described_class.cloud }.to raise_error(PhilipsHue::ConnectionError)
    end

    it 'raises ParseError on invalid JSON' do
      stub_request(:get, 'https://discovery.meethue.com').to_return(status: 200, body: 'not json')

      expect { described_class.cloud }.to raise_error(PhilipsHue::ParseError)
    end
  end

  describe '.parse_message' do
    # Build a representative mDNS response, round-trip it through encode/decode,
    # then feed the decoded message to the pure parser. No sockets are involved.
    def decoded_message
      instance = '001788fffe1234ab._hue._tcp.local.'
      message = Resolv::DNS::Message.new(0)
      message.qr = 1
      message.add_answer('_hue._tcp.local.', 120,
                         Resolv::DNS::Resource::IN::PTR.new(Resolv::DNS::Name.create(instance)))
      message.add_additional(instance, 120, Resolv::DNS::Resource::IN::A.new('192.168.1.42'))
      message.add_additional(instance, 120, Resolv::DNS::Resource::IN::TXT.new('bridgeid=001788FFFE1234AB'))
      Resolv::DNS::Message.decode(message.encode)
    end

    it 'extracts a bridge hash with the IP and the TXT bridgeid' do
      bridges = described_class.parse_message(decoded_message)

      expect(bridges.size).to eq(1)
      expect(bridges.first['internalipaddress']).to eq('192.168.1.42')
      expect(bridges.first['id']).to eq('001788FFFE1234AB')
      expect(bridges.first['port']).to eq(443)
    end

    it 'produces hashes consumable by BridgeInfo.from_api' do
      bridge = PhilipsHue::BridgeInfo.from_api(described_class.parse_message(decoded_message).first)

      expect(bridge.internal_ip_address).to eq('192.168.1.42')
      expect(bridge.id).to eq('001788FFFE1234AB')
    end

    it 'falls back to the PTR instance name when no TXT bridgeid is present' do
      instance = '001788fffe9999zz._hue._tcp.local.'
      message = Resolv::DNS::Message.new(0)
      message.qr = 1
      message.add_answer('_hue._tcp.local.', 120,
                         Resolv::DNS::Resource::IN::PTR.new(Resolv::DNS::Name.create(instance)))
      message.add_additional(instance, 120, Resolv::DNS::Resource::IN::A.new('192.168.1.50'))
      decoded = Resolv::DNS::Message.decode(message.encode)

      bridge = described_class.parse_message(decoded).first

      expect(bridge['internalipaddress']).to eq('192.168.1.50')
      expect(bridge['id']).to eq('001788fffe9999zz')
    end
  end

  describe '.discover' do
    let(:mdns_bridge) { PhilipsHue::BridgeInfo.from_api('internalipaddress' => '10.0.0.1', 'id' => 'mdns') }
    let(:cloud_bridge) { PhilipsHue::BridgeInfo.from_api('internalipaddress' => '10.0.0.2', 'id' => 'cloud') }

    it 'returns mDNS results first when mdns is preferred and yields bridges' do
      allow(described_class).to receive_messages(mdns: [mdns_bridge], cloud: [cloud_bridge])

      expect(described_class.discover).to eq([mdns_bridge])
      expect(described_class).not_to have_received(:cloud)
    end

    it 'falls back to cloud when the preferred mdns strategy is empty' do
      allow(described_class).to receive_messages(mdns: [], cloud: [cloud_bridge])

      expect(described_class.discover).to eq([cloud_bridge])
    end

    it 'falls back to cloud when the preferred mdns strategy raises' do
      allow(described_class).to receive(:mdns).and_raise(StandardError)
      allow(described_class).to receive(:cloud).and_return([cloud_bridge])

      expect(described_class.discover).to eq([cloud_bridge])
    end

    it 'tries cloud first when cloud is preferred' do
      allow(described_class).to receive_messages(mdns: [mdns_bridge], cloud: [cloud_bridge])

      expect(described_class.discover(prefer: :cloud)).to eq([cloud_bridge])
      expect(described_class).not_to have_received(:mdns)
    end

    it 'returns an empty array when both strategies are empty' do
      allow(described_class).to receive_messages(mdns: [], cloud: [])

      expect(described_class.discover).to eq([])
    end
  end
end
