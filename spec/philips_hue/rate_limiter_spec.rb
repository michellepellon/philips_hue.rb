# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PhilipsHue::RateLimiter do
  # A controllable clock and sleeper so the limiter's timing is deterministic.
  let(:now) { [0.0] }
  let(:clock) { -> { now[0] } }
  let(:slept) { [] }
  let(:sleeper) do
    lambda do |seconds|
      slept << seconds
      now[0] += seconds # simulate time passing while we "sleep"
    end
  end

  subject(:limiter) do
    described_class.new(rate: 10, capacity: 10, clock: clock, sleeper: sleeper)
  end

  it 'grants a full bucket of tokens without sleeping' do
    10.times { limiter.acquire }
    expect(slept).to be_empty
  end

  it 'blocks once the bucket is empty, waiting ~1/rate per extra token' do
    10.times { limiter.acquire } # drain the bucket
    limiter.acquire              # 11th must wait
    expect(slept.sum).to be_within(1e-9).of(0.1) # 1 token / 10 per second
  end

  it 'refills tokens as time passes' do
    10.times { limiter.acquire }
    now[0] += 0.5 # half a second -> 5 tokens back at rate 10
    5.times { limiter.acquire }
    expect(slept).to be_empty
  end

  it 'never exceeds capacity when idle for a long time' do
    now[0] += 100
    limiter.acquire
    now[0] += 100
    # Only capacity tokens should be available, not 1000+.
    expect { 10.times { limiter.acquire } }.not_to raise_error
    limiter.acquire
    expect(slept).not_to be_empty
  end

  it 'defaults capacity to the rate' do
    limiter = described_class.new(rate: 5, clock: clock, sleeper: sleeper)
    expect(limiter.capacity).to eq(5.0)
  end
end
