# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PhilipsHue::EventStream do
  let(:ip) { '192.168.1.42' }
  let(:app_key) { 'test-app-key' }
  let(:slept) { [] }
  let(:sleeper) { ->(seconds) { slept << seconds } }

  subject(:stream) do
    described_class.new(ip: ip, app_key: app_key, sleeper: sleeper, backoff_base: 0.5, max_backoff: 8.0)
  end

  # A single SSE event whose data is a JSON array of one update event object.
  def sse_event(id: 'e1', light_id: 'L1', on: false)
    payload = [{
      'creationtime' => '2026-01-01T00:00:00Z',
      'id' => id,
      'type' => 'update',
      'data' => [{ 'id' => light_id, 'type' => 'light', 'on' => { 'on' => on } }]
    }]
    "data: #{JSON.dump(payload)}\n\n"
  end

  describe '#feed' do
    it 'yields a HueEvent for a complete data block terminated by a blank line' do
      events = []
      stream.feed(sse_event(id: 'abc')) { |event| events << event }

      expect(events.size).to eq(1)
      expect(events.first).to be_a(PhilipsHue::HueEvent)
      expect(events.first.id).to eq('abc')
      expect(events.first.type).to eq('update')
      expect(events.first.data.first['id']).to eq('L1')
    end

    it 'buffers an event whose data is split across two chunks' do
      whole = sse_event(id: 'split')
      head = whole[0, 20]
      tail = whole[20..]
      events = []

      stream.feed(head) { |event| events << event }
      expect(events).to be_empty

      stream.feed(tail) { |event| events << event }
      expect(events.map(&:id)).to eq(['split'])
    end

    it 'yields multiple events delivered in a single chunk' do
      chunk = sse_event(id: 'one') + sse_event(id: 'two')
      events = []

      stream.feed(chunk) { |event| events << event }

      expect(events.map(&:id)).to eq(%w[one two])
    end

    it 'ignores SSE comment/keepalive lines' do
      chunk = ": hi\n\n#{sse_event(id: 'real')}"
      events = []

      stream.feed(chunk) { |event| events << event }

      expect(events.map(&:id)).to eq(['real'])
    end

    it 'yields one HueEvent per object when a data array carries several' do
      payload = [
        { 'id' => 'a', 'type' => 'update', 'data' => [] },
        { 'id' => 'b', 'type' => 'add', 'data' => [] }
      ]
      events = []

      stream.feed("data: #{JSON.dump(payload)}\n\n") { |event| events << event }

      expect(events.map(&:id)).to eq(%w[a b])
    end
  end

  describe '#each' do
    it 'reconnects after a transient disconnect and delivers the next event' do
      stub_request(:get, "https://#{ip}/eventstream/clip/v2")
        .to_raise(Errno::ECONNRESET).then
        .to_return(status: 200, body: sse_event(id: 'after-reconnect'))

      received = []
      stream.each do |event|
        received << event
        stream.stop
      end

      expect(received.map(&:id)).to eq(['after-reconnect'])
      expect(slept).not_to be_empty
      expect(slept.first).to eq(0.5) # backoff_base used for the first retry
    end

    it 'sends the application key and SSE accept headers' do
      stub = stub_request(:get, "https://#{ip}/eventstream/clip/v2")
             .with(headers: { 'hue-application-key' => app_key, 'Accept' => 'text/event-stream' })
             .to_return(status: 200, body: sse_event(id: 'hdr'))

      stream.each { |_event| stream.stop }

      expect(stub).to have_been_requested
    end

    it 'returns an Enumerator when called without a block' do
      expect(stream.each).to be_a(Enumerator)
    end
  end
end
