require "ld-eventsource"

require "http_stub"

module SSE
  module Impl
    describe Backoff do
      it "increases exponentially with jitter" do
        initial = 1.5
        max = 60
        b = Backoff.new(initial, max)
        previous = 0

        for i in 1..6 do
          interval = b.next_interval
          expect(interval).to be > previous
          target = initial * (2 ** (i - 1))
          expect(interval).to be <= target
          expect(interval).to be >= target / 2
          previous = i
        end

        interval = b.next_interval
        expect(interval).to be >= previous
        expect(interval).to be <= max
      end

      it "resets to initial delay if reset threshold has elapsed" do
        initial = 1.5
        max = 60
        threshold = 2
        b = Backoff.new(initial, max, reconnect_reset_interval: threshold)

        for i in 1..6 do
          # just cause the backoff to increase quickly, don't actually do these delays
          b.next_interval
        end

        b.mark_success
        sleep(threshold + 0.001)

        interval = b.next_interval
        expect(interval).to be <= initial
        expect(interval).to be >= initial / 2

        interval = b.next_interval # make sure it continues increasing after that
        expect(interval).to be <= (initial * 2)
        expect(interval).to be >= initial
      end

      it "always returns zero if the initial delay is zero" do
        initial = 0
        max = 60
        b = Backoff.new(initial, max)

        for i in 1..6 do
          interval = b.next_interval
          expect(interval).to eq(0)
        end
      end

      it "always returns zero if the initial delay is 0.0" do
        b = Backoff.new(0.0, 60)

        6.times do
          expect(b.next_interval).to eq(0)
        end
      end

      it "doubles the delay for each attempt until it reaches the maximum" do
        max = 30
        b = Backoff.new(1, max)

        [1, 2, 4, 8, 16, 30, 30, 30].each do |target|
          interval = b.next_interval
          expect(interval).to be >= target / 2.0
          expect(interval).to be <= target
        end
      end

      it "stops doubling the delay after it reaches the maximum" do
        b = Backoff.new(1, 4)
        100.times { b.next_interval }

        # The delay doubled twice to reach the maximum of 4. If the doubling had continued, a
        # smaller initial delay would still give the maximum.
        b.base_interval = 0.5
        interval = b.next_interval
        expect(interval).to be >= 1
        expect(interval).to be < 2
      end

      [0.0, 1.0].each do |initial|
        it "returns a finite interval after many attempts with a Float initial delay of #{initial}" do
          max = 30
          b = Backoff.new(initial, max)

          1100.times do
            interval = b.next_interval
            expect(interval).to be_finite
            expect(interval).to be_between(0, max)
          end
        end
      end
    end
  end
end
