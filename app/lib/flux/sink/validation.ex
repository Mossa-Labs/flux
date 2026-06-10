defmodule Flux.Sink.Validation do
  @moduledoc """
  Small helper for writing `c:Flux.Sink.Adapter.validate_config/1` clauses
  declaratively.

  Each adapter expresses its rules as a list of single-argument *rule*
  functions. A rule receives the config map and returns `:ok` when satisfied or
  `{:error, message}` when not. `run/2` applies every rule, collects the failing
  messages in order, and shapes them into the
  `t:Flux.Sink.Adapter.validation_result/0` the behaviour expects.

      def validate_config(config) do
        Flux.Sink.Validation.run(config, [
          &validate_url/1,
          &validate_method/1
        ])
      end

  This keeps the orchestration flat and gives every rule a descriptive name,
  rather than threading an `errors` accumulator through a stack of `if`/`case`
  blocks.
  """

  @type config :: map()
  @type rule :: (config() -> :ok | {:error, String.t()})

  @doc """
  Runs `rules` against `config`, returning `:ok` if all pass or
  `{:error, messages}` with one message per failing rule, in declaration order.
  """
  @spec run(config(), [rule()]) :: :ok | {:error, [String.t()]}
  def run(config, rules) do
    case Enum.flat_map(rules, &apply_rule(&1, config)) do
      [] -> :ok
      messages -> {:error, messages}
    end
  end

  defp apply_rule(rule, config) do
    case rule.(config) do
      :ok -> []
      {:error, message} -> [message]
    end
  end
end
