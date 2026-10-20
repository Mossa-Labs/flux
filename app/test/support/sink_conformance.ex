defmodule Flux.SinkConformance do
  @moduledoc """
  Shared contract tests every sink adapter must pass.

  `use` it inside an adapter's test module (after `use ExUnit.Case` or a case
  template) to add a `"sink adapter conformance"` describe block:

      use Flux.SinkConformance,
        adapter: Flux.Sink.Adapters.HTTP,
        type: "http",
        valid_config: %{"url" => "https://example.com/hook"},
        invalid_configs: [%{}, %{"url" => "nope"}]

  Options:

    * `:adapter` / `:type` (required) — the module and its registry type.
    * `:valid_config` (required) — a config `validate_config/1` must accept.
    * `:invalid_configs` (required) — configs it must reject with string messages.
    * `:deliver_config` — opt in to delivery checks: `deliver/3` with this config
      must return a well-formed result (never raise) for a range of record
      shapes. Use a destination that fails fast where there is no test server.
    * `:test_connection_config` — opt in to `test_connection/1` shape checks.
  """

  defmacro __using__(opts) do
    deliver? = Keyword.has_key?(opts, :deliver_config)
    test_connection? = Keyword.has_key?(opts, :test_connection_config)

    quote do
      describe "sink adapter conformance" do
        @conformance unquote(opts)

        test "implements the Flux.Sink.Adapter behaviour" do
          adapter = @conformance[:adapter]

          behaviours =
            adapter.module_info(:attributes) |> Keyword.get_values(:behaviour) |> List.flatten()

          assert Flux.Sink.Adapter in behaviours
        end

        test "is registered under its type" do
          assert {:ok, @conformance[:adapter]} == Flux.Sink.Registry.lookup(@conformance[:type])
        end

        test "its type is an accepted sink schema type" do
          changeset =
            Flux.Sinks.Sink.changeset(%Flux.Sinks.Sink{}, %{
              name: "conformance",
              type: @conformance[:type],
              organization_id: 1,
              config: @conformance[:valid_config]
            })

          refute Keyword.has_key?(changeset.errors, :type)
          refute Keyword.has_key?(changeset.errors, :config)
        end

        test "validate_config/1 accepts the valid config" do
          assert :ok == @conformance[:adapter].validate_config(@conformance[:valid_config])
        end

        test "validate_config/1 rejects each invalid config with string messages" do
          for config <- @conformance[:invalid_configs] do
            assert {:error, [_ | _] = messages} = @conformance[:adapter].validate_config(config),
                   "expected #{inspect(config)} to be rejected"

            assert Enum.all?(messages, &is_binary/1)
          end
        end

        if unquote(test_connection?) do
          test "test_connection/1 returns :ok or {:error, reason}" do
            result = @conformance[:adapter].test_connection(@conformance[:test_connection_config])
            assert result == :ok or match?({:error, _}, result)
          end
        end

        if unquote(deliver?) do
          @tag :capture_log
          test "deliver/3 returns a well-formed result for any record shape" do
            records = [
              %{"id" => 1, "name" => "alpha"},
              %{"id" => 2, "nested" => %{"a" => [1, 2, 3]}, "flag" => true},
              %{id: 3, event: "atom keys"},
              %{}
            ]

            config = Map.put(@conformance[:deliver_config], "type", @conformance[:type])

            for record <- records do
              result =
                @conformance[:adapter].deliver(record, config,
                  pipeline_id: "conformance",
                  message_id: Ecto.UUID.generate()
                )

              assert result == :ok or match?({:ok, _}, result) or match?({:error, _}, result),
                     "unexpected deliver/3 result for #{inspect(record)}: #{inspect(result)}"
            end
          end
        end
      end
    end
  end
end
