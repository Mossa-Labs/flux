defmodule Flux.SourceTest do
  use ExUnit.Case, async: true

  alias Flux.Source

  describe "adapter_for_type/1" do
    test "returns Webhook adapter for \"webhook\"" do
      assert {:ok, Flux.Source.Adapters.Webhook} = Source.adapter_for_type("webhook")
    end

    test "returns Poll adapter for \"poll\"" do
      assert {:ok, Flux.Source.Adapters.Poll} = Source.adapter_for_type("poll")
    end

    test "returns Stub adapter for \"kafka\" in Community (real Kafka is Pro)" do
      assert {:ok, Flux.Source.Adapters.Stub} = Source.adapter_for_type("kafka")
    end

    test "returns Stub adapter for \"sqs\" in Community (real SQS is Pro)" do
      assert {:ok, Flux.Source.Adapters.Stub} = Source.adapter_for_type("sqs")
    end

    test "returns error for unknown type" do
      assert {:error, :unknown_type} = Source.adapter_for_type("unknown")
    end
  end

  describe "queue_name/2 — the source→pipeline linkage convention" do
    test "webhook derives webhooks.<source>" do
      assert "webhooks.github" = Source.queue_name("webhook", %{"source" => "github"})
    end

    test "poll derives polling.<source_id>" do
      assert "polling.orders" = Source.queue_name("poll", %{"source_id" => "orders"})
    end

    test "unknown type returns error" do
      assert {:error, {:unknown_source_type, "nope"}} = Source.queue_name("nope", %{})
    end
  end

  describe "ingestion_spec/3" do
    test "passive Community sources have no ingestion process" do
      assert nil == Source.ingestion_spec("webhook", %{"source" => "github"})
      assert nil == Source.ingestion_spec("poll", %{"source_id" => "orders"})
    end

    test "the Pro Kafka stub starts nothing in Community" do
      assert nil == Source.ingestion_spec("kafka", %{"type" => "kafka", "topic" => "events"})
    end

    test "the Pro SQS stub starts nothing in Community" do
      assert nil == Source.ingestion_spec("sqs", %{"type" => "sqs", "queue_url" => "https://q"})
    end
  end

  describe "validate_config/2" do
    test "webhook requires a source name" do
      assert :ok = Source.validate_config("webhook", %{"source" => "github"})
      assert {:error, ["source is required"]} = Source.validate_config("webhook", %{})
    end

    test "poll requires a source_id and a valid url if present" do
      assert :ok = Source.validate_config("poll", %{"source_id" => "orders"})

      assert {:error, errors} =
               Source.validate_config("poll", %{"source_id" => "x", "url" => "not a url"})

      assert "url must be a valid http(s) URL" in errors
    end

    test "Community kafka delegates to Stub and returns a pro_required message" do
      config = %{"type" => "kafka", "topic" => "events"}
      assert {:error, [msg]} = Source.validate_config("kafka", config)
      assert msg =~ "Flux Pro"
    end

    test "Community sqs delegates to Stub and returns a pro_required message" do
      config = %{"type" => "sqs", "queue_url" => "https://q"}
      assert {:error, [msg]} = Source.validate_config("sqs", config)
      assert msg =~ "Flux Pro"
    end

    test "returns error for unknown source type" do
      assert {:error, ["unknown source type: nope"]} = Source.validate_config("nope", %{})
    end
  end

  describe "test_connection/2" do
    test "passive sources without a test_connection callback return :ok" do
      assert :ok = Source.test_connection("webhook", %{"source" => "github"})
    end

    test "Community kafka stub surfaces a structured pro_required tuple" do
      assert {:error, {:pro_required, :kafka_source}} =
               Source.test_connection("kafka", %{"type" => "kafka"})
    end

    test "Community sqs stub surfaces a structured pro_required tuple" do
      assert {:error, {:pro_required, :sqs_source}} =
               Source.test_connection("sqs", %{"type" => "sqs"})
    end
  end
end
