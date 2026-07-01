# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PhilipsHue::HueEvent do
  let(:payload) do
    {
      'creationtime' => '2026-01-15T12:30:00Z',
      'id' => 'evt-uuid',
      'type' => 'update',
      'data' => [{ 'id' => '3a5f9b2c-uuid', 'type' => 'light', 'on' => { 'on' => false } }]
    }
  end

  describe '.from_api' do
    subject(:event) { described_class.from_api(payload) }

    it 'maps identifiers and type' do
      expect(event.id).to eq('evt-uuid')
      expect(event.type).to eq('update')
    end

    it 'parses the creation time into a Time' do
      expect(event.creationtime).to be_a(Time)
      expect(event.creationtime.utc.hour).to eq(12)
    end

    it 'keeps data as raw resource snapshots' do
      expect(event.data.first['id']).to eq('3a5f9b2c-uuid')
    end

    it 'defaults data to an empty array when absent' do
      event = described_class.from_api('type' => 'update')
      expect(event.data).to eq([])
    end
  end

  describe 'type predicates' do
    it 'reports the matching predicate true and others false' do
      event = described_class.from_api(payload)
      expect(event.update?).to be(true)
      expect(event.add?).to be(false)
      expect(event.delete?).to be(false)
      expect(event.error?).to be(false)
    end
  end

  it 'defines the recognised event types' do
    expect(described_class::TYPES).to eq(%w[update add delete error])
  end
end
