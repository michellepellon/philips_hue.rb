# frozen_string_literal: true

module PhilipsHue
  # A thread-safe token-bucket rate limiter.
  #
  # The Bridge silently drops commands that exceed roughly 10/second to
  # individual lights and 1/second to groups. {Client} keeps one limiter per
  # ceiling and calls {#acquire} before each write, which blocks just long
  # enough to stay under the limit while still allowing short bursts up to the
  # bucket capacity.
  #
  # @example
  #   limiter = PhilipsHue::RateLimiter.new(rate: 10)
  #   limiter.acquire   # returns immediately while tokens remain
  #   limiter.acquire   # blocks once the bucket is empty
  class RateLimiter
    # Tolerance applied when checking for an available token.
    #
    # The bucket level is derived from `monotonic_clock_now - last_refill`, and
    # for a long-running process the monotonic clock holds large values whose
    # floating-point ULP is comparable to the per-refill rounding error. Without
    # a tolerance the level can settle a few ULPs below 1.0 while the corrective
    # wait rounds away to nothing, spinning forever. A microtoken of slack is
    # negligible for rate limiting and eliminates that failure mode.
    # @return [Float]
    EPSILON = 1e-6

    # @return [Float] tokens replenished per second
    attr_reader :rate

    # @return [Float] maximum number of tokens the bucket can hold
    attr_reader :capacity

    # Initialize a new rate limiter.
    #
    # @param rate [Numeric] tokens added per second (the sustained command rate)
    # @param capacity [Numeric, nil] maximum burst size; defaults to `rate`
    # @param clock [#call] monotonic clock returning seconds as a Float;
    #   injectable for testing
    # @param sleeper [#call] callable invoked with a duration to wait;
    #   injectable for testing
    def initialize(rate:, capacity: nil, clock: nil, sleeper: nil)
      @rate = rate.to_f
      @capacity = (capacity || rate).to_f
      @tokens = @capacity
      @clock = clock || -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
      @sleeper = sleeper || ->(seconds) { sleep(seconds) }
      @last = @clock.call
      @mutex = Mutex.new
    end

    # Acquire a single token, blocking until one is available.
    #
    # @return [void]
    def acquire
      loop do
        wait = nil
        @mutex.synchronize do
          refill
          if @tokens >= 1.0 - EPSILON
            @tokens -= 1.0
            return nil
          end
          wait = (1.0 - @tokens) / @rate
        end
        @sleeper.call(wait)
      end
    end

    private

    # Add tokens accrued since the last refill, capped at capacity.
    #
    # @return [void]
    def refill
      now = @clock.call
      elapsed = now - @last
      @last = now
      @tokens = [@capacity, @tokens + (elapsed * @rate)].min
    end
  end
end
