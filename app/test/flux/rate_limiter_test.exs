defmodule Flux.RateLimiterTest do
  # async: false — the limiter owns one global, named ETS table.
  use ExUnit.Case, async: false

  alias Flux.RateLimiter

  setup do
    RateLimiter.reset()
    on_exit(&RateLimiter.reset/0)
    :ok
  end

  test "permits up to the limit then denies within a window" do
    key = {:t, System.unique_integer()}

    assert RateLimiter.allow?(key, 3, 60_000)
    assert RateLimiter.allow?(key, 3, 60_000)
    assert RateLimiter.allow?(key, 3, 60_000)
    refute RateLimiter.allow?(key, 3, 60_000)
  end

  test "keys are independent" do
    assert RateLimiter.allow?(:a, 1, 60_000)
    refute RateLimiter.allow?(:a, 1, 60_000)
    # A different key has its own budget.
    assert RateLimiter.allow?(:b, 1, 60_000)
  end

  test "rolls over to a fresh window" do
    key = {:t, System.unique_integer()}

    assert RateLimiter.allow?(key, 1, 20)
    refute RateLimiter.allow?(key, 1, 20)
    Process.sleep(25)
    assert RateLimiter.allow?(key, 1, 20)
  end

  test "reset/0 clears all counters" do
    assert RateLimiter.allow?(:c, 1, 60_000)
    refute RateLimiter.allow?(:c, 1, 60_000)

    RateLimiter.reset()
    assert RateLimiter.allow?(:c, 1, 60_000)
  end
end
