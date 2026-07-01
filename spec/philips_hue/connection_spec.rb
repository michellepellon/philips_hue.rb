# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PhilipsHue::Connection do
  before { described_class.reset_warning! }

  describe '.normalize_tls' do
    it 'treats a string as strict mode with that path as the CA bundle' do
      expect(described_class.normalize_tls('/path/ca.pem', nil)).to eq([true, '/path/ca.pem'])
    end

    it 'prefers an explicit ca_bundle over a string verify_tls' do
      expect(described_class.normalize_tls('/ignored.pem', '/explicit.pem')).to eq([true, '/explicit.pem'])
    end

    it 'maps false and nil to disabled verification' do
      expect(described_class.normalize_tls(false, nil)).to eq([false, nil])
      expect(described_class.normalize_tls(nil, nil)).to eq([false, nil])
    end

    it 'maps true to enabled verification' do
      expect(described_class.normalize_tls(true, nil)).to eq([true, nil])
    end
  end

  describe '.build_http' do
    it 'defaults to TLS with verification disabled and warns once' do
      expect { @http = described_class.build_http(ip: '192.168.1.42') }
        .to output(/TLS verification is disabled/).to_stderr
      expect(@http.use_ssl?).to be(true)
      expect(@http.verify_mode).to eq(OpenSSL::SSL::VERIFY_NONE)
      expect(@http.address).to eq('192.168.1.42')
    end

    it 'only warns about insecure TLS once per process' do
      expect { described_class.build_http(ip: '1.1.1.1') }.to output.to_stderr
      expect { described_class.build_http(ip: '1.1.1.1') }.not_to output.to_stderr
    end

    it 'enables peer verification with a CA bundle in strict mode' do
      http = described_class.build_http(ip: '192.168.1.42', verify_tls: '/path/ca.pem')
      expect(http.verify_mode).to eq(OpenSSL::SSL::VERIFY_PEER)
      expect(http.ca_file).to eq('/path/ca.pem')
    end

    it 'overrides the TLS hostname to the Bridge ID while connecting to the IP in strict mode' do
      http = described_class.build_http(
        ip: '192.168.1.42', verify_tls: '/path/ca.pem', bridge_id: '001788fffe1234ab'
      )
      expect(http.address).to eq('001788fffe1234ab')
      expect(http.ipaddr).to eq('192.168.1.42')
    end

    it 'does not override the hostname when verification is disabled' do
      http = described_class.build_http(ip: '192.168.1.42', bridge_id: '001788fffe1234ab')
      expect(http.address).to eq('192.168.1.42')
    end

    it 'applies the supplied timeouts' do
      http = described_class.build_http(ip: '1.1.1.1', open_timeout: 3, read_timeout: 7)
      expect(http.open_timeout).to eq(3)
      expect(http.read_timeout).to eq(7)
    end
  end
end
