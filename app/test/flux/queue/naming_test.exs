defmodule Flux.Queue.NamingTest do
  use ExUnit.Case, async: true

  alias Flux.Queue.Naming

  doctest Flux.Queue.Naming

  describe "validate_logical/1" do
    test "accepts ordinary logical names" do
      for name <- [
            "webhooks.stripe",
            "polling.feed",
            "default",
            "a",
            "9lives",
            "ingest.group-1.topic_A",
            "orders.v2.archive",
            String.duplicate("a", 200)
          ] do
        assert :ok = Naming.validate_logical(name), "expected #{inspect(name)} to be valid"
      end
    end

    test "refuses names that reach outside the organization" do
      for name <- ["org.1.x", "ORG.1.x", "Org.x", "amq.gen", "flux.dlq", "FLUX.events"] do
        assert {:error, :reserved_prefix} = Naming.validate_logical(name)
      end
    end

    test "refuses names a broker can't use" do
      assert {:error, :blank} = Naming.validate_logical("")
      assert {:error, :blank} = Naming.validate_logical(nil)
      assert {:error, :too_long} = Naming.validate_logical(String.duplicate("a", 201))

      for name <- ["a b", "a*", "a.#", ".a", "_a", "-a", "a/b", "ä", "a\nb", "a\u0000"] do
        assert {:error, :invalid_characters} = Naming.validate_logical(name),
               "expected #{inspect(name)} to be refused"
      end

      assert {:error, :invalid_characters} = Naming.validate_logical(:atom)
      assert {:error, :invalid_characters} = Naming.validate_logical(42)
    end

    test "every error has a message" do
      for reason <- [:blank, :too_long, :invalid_characters, :reserved_prefix] do
        assert is_binary(Naming.error_message(reason))
      end
    end
  end

  describe "physical/2" do
    test "places the logical name inside the organization" do
      assert {:ok, "org.7.webhooks.stripe"} = Naming.physical(7, "webhooks.stripe")
    end

    test "fits the broker's 255-byte limit for the longest name and organization id" do
      {:ok, name} = Naming.physical(9_223_372_036_854_775_807, String.duplicate("a", 200))
      assert byte_size(name) <= 255
    end

    test "refuses an invalid organization or name" do
      for org <- [nil, 0, -1, "7", 1.0] do
        assert {:error, :organization_required} = Naming.physical(org, "q")
      end

      assert {:error, :reserved_prefix} = Naming.physical(7, "org.8.q")
    end

    test "physical!/2 raises on invalid input" do
      assert Naming.physical!(7, "q") == "org.7.q"
      assert_raise ArgumentError, fn -> Naming.physical!(7, "org.8.q") end
    end
  end

  describe "owner/1 and logical/2" do
    test "round-trip a physical name" do
      physical = Naming.physical!(12, "webhooks.stripe")

      assert {:ok, 12, "webhooks.stripe"} = Naming.owner(physical)
      assert {:ok, "webhooks.stripe"} = Naming.logical(12, physical)
    end

    test "are unambiguous between organizations whose ids share digits" do
      assert {:ok, 1, "2.x"} = Naming.owner("org.1.2.x")
      assert {:ok, 12, "x"} = Naming.owner("org.12.x")
      assert :error = Naming.logical(1, "org.12.x")
      assert :error = Naming.logical(12, "org.1.2.x")
    end

    test "don't recognize names outside the namespace" do
      for name <- ["webhooks.stripe", "org.x.q", "org.01.q", "org.0.q", "org.1", "org.1.", nil] do
        assert :error = Naming.owner(name), "expected #{inspect(name)} not to parse"
      end
    end

    test "logical/2 refuses another organization's queue and the organization's system queues" do
      assert :error = Naming.logical(7, "org.8.webhooks.stripe")
      assert :error = Naming.logical(7, Naming.dead_letter_queue(7))
      assert :error = Naming.logical(nil, "org.7.q")
    end
  end

  describe "check_owner/2" do
    test "accepts only the organization's own queues" do
      assert :ok = Naming.check_owner("org.7.q", 7)
      assert {:error, :organization_mismatch} = Naming.check_owner("org.8.q", 7)
      assert {:error, :organization_mismatch} = Naming.check_owner("q", 7)
      assert {:error, :organization_required} = Naming.check_owner("org.7.q", nil)
    end
  end

  describe "dead_letter_queue/1" do
    test "is inside the organization, under a prefix no logical name can use" do
      dlq = Naming.dead_letter_queue(7)

      assert {:ok, 7, "flux.dlq"} = Naming.owner(dlq)
      assert {:error, :reserved_prefix} = Naming.validate_logical("flux.dlq")
    end
  end

  describe "sanitize_segment/1" do
    test "keeps a valid segment unchanged" do
      for text <- ["orders", "orders.fifo", "Topic-1_a"] do
        assert Naming.sanitize_segment(text) == text
      end
    end

    test "turns arbitrary text into a valid segment" do
      for text <- ["sensors/+/temp", "a#", "~sub%", ".hidden", "", "ünïcödé", "a b c"] do
        segment = Naming.sanitize_segment(text)
        assert :ok = Naming.validate_logical("x." <> segment), "for #{inspect(text)}"
        assert Regex.match?(~r/\A[A-Za-z0-9]/, segment)
      end
    end

    test "shortens long text, keeping distinct inputs distinct" do
      a = Naming.sanitize_segment(String.duplicate("a", 300) <> "1")
      b = Naming.sanitize_segment(String.duplicate("a", 300) <> "2")

      assert byte_size(a) <= 120
      assert a != b
      assert :ok = Naming.validate_logical("external." <> a)
    end
  end
end
