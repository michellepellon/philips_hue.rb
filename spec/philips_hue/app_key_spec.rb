# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PhilipsHue::AppKey do
  describe '.from_api' do
    subject(:key) { described_class.from_api('username' => 'APPKEY123', 'clientkey' => 'DEADBEEF') }

    it 'maps username and clientkey' do
      expect(key.username).to eq('APPKEY123')
      expect(key.clientkey).to eq('DEADBEEF')
    end

    it 'exposes the username as app_key' do
      expect(key.app_key).to eq('APPKEY123')
    end
  end

  describe '.new' do
    it 'accepts keyword arguments' do
      key = described_class.new(username: 'u', clientkey: 'c')
      expect(key.app_key).to eq('u')
    end

    it 'tolerates a missing clientkey' do
      key = described_class.from_api('username' => 'u')
      expect(key.clientkey).to be_nil
    end
  end
end
