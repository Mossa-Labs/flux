# Testing Iteration 3: The Engine & Intelligence (Archived)

> **Archived**: This QA checklist was used during pipeline engine development. See [developer_guide.md](../developer_guide.md) for current testing conventions and [lua_scripting.md](../lua_scripting.md) for Lua script testing.

This guide walks you through testing the pipeline execution engine and AI anomaly detection features.

## Prerequisites

1. Start the application:
   ```bash
   cd app
   mix ecto.migrate
   mix phx.server
   ```

2. Open an IEx session (in a separate terminal):
   ```bash
   cd app
   iex -S mix
   ```

## 1. Create a Test Organization

First, you need an organization to associate pipelines with:

```elixir
# In iex
alias Flux.Repo
alias Flux.Structure.Organization

# Create a test organization
{:ok, org} = Repo.insert(%Organization{
  name: "Test Org",
  slug: "test-org",
  user_id: 1  # Use an existing user ID or create a user first
})

org_id = org.id
```

## 2. Create a Simple Pipeline

Create a pipeline with basic transformation steps:

```elixir
alias Flux.Pipelines

# Create a pipeline that renames a field and filters by type
{:ok, pipeline} = Pipelines.create_pipeline(%{
  name: "webhook-processor",
  source_queue: "webhooks.test",
  destination_queue: "processed.test",
  organization_id: org_id,
  status: "stopped",
  config: %{
    "producer" => %{"concurrency" => 1},
    "processors" => %{"concurrency" => 5}
  },
  steps: %{
    "version" => "1.0",
    "steps" => [
      %{
        "id" => "s1",
        "type" => "native",
        "operation" => "rename",
        "config" => %{"from" => "event", "to" => "event_type"}
      },
      %{
        "id" => "s2",
        "type" => "native",
        "operation" => "filter",
        "config" => %{
          "field" => "event_type",
          "operator" => "in",
          "values" => ["push", "pull_request", "issue"]
        }
      }
    ]
  }
})

IO.puts("Created pipeline: #{pipeline.id}")
```

## 3. Start the Pipeline

```elixir
alias Flux.Pipeline.Manager

# Start the pipeline
{:ok, _pid} = Manager.start_pipeline(pipeline.id)

# Verify it's running
Manager.get_status(pipeline.id)
# => :running

# List all running pipelines
Manager.list_running()
```

## 4. Send Test Messages

Push messages through the pipeline using the Memory producer:

```elixir
alias Flux.Pipeline.Producers.Memory

# Send a message that should pass the filter
Memory.push_message("webhooks.test", %{
  "event" => "push",
  "repository" => "flux",
  "user" => "developer"
})

# Send a message that should be filtered out
Memory.push_message("webhooks.test", %{
  "event" => "fork",
  "repository" => "flux"
})

# Send another valid message
Memory.push_message("webhooks.test", %{
  "event" => "pull_request",
  "action" => "opened",
  "number" => 42
})
```

Check the logs - you should see:
- The first message processed (renamed `event` to `event_type`)
- The second message skipped (filtered out - "fork" not in allowed values)
- The third message processed

## 5. Test the Interpreter Directly

You can test transformation steps without starting a pipeline:

```elixir
alias Flux.Pipeline.Interpreter

# Test data
data = %{
  "user" => %{"name" => "John", "email" => "JOHN@EXAMPLE.COM"},
  "amount" => 150,
  "type" => "purchase"
}

# Pipeline config with multiple steps
config = %{
  "version" => "1.0",
  "steps" => [
    %{
      "id" => "extract",
      "type" => "native",
      "operation" => "map",
      "config" => %{"field" => "user.email", "to" => "email"}
    },
    %{
      "id" => "filter-high-value",
      "type" => "native",
      "operation" => "filter",
      "config" => %{"field" => "amount", "operator" => "gte", "value" => 100}
    }
  ]
}

{:ok, result} = Interpreter.execute(data, config)
IO.inspect(result)
# => %{"user" => ..., "amount" => 150, "type" => "purchase", "email" => "JOHN@EXAMPLE.COM"}
```

## 6. Test Lua Scripts

Test custom Lua transformations:

```elixir
alias Flux.Pipeline.Steps.Script

data = %{
  "name" => "John Doe",
  "email" => "JOHN@EXAMPLE.COM",
  "items" => [
    %{"price" => 10, "quantity" => 2},
    %{"price" => 25, "quantity" => 1}
  ]
}

config = %{
  "code" => """
  function transform(data)
    -- Normalize email
    data.email = string.lower(data.email)

    -- Add timestamp
    data.processed_at = os.time()

    -- Calculate total
    local total = 0
    if data.items then
      for i, item in ipairs(data.items) do
        total = total + (item.price * item.quantity)
      end
    end
    data.total = total

    return data
  end
  """,
  "timeout_ms" => 5000
}

{:ok, result} = Script.execute(data, config)
IO.inspect(result)
# => %{
#   "name" => "John Doe",
#   "email" => "john@example.com",
#   "items" => [...],
#   "processed_at" => 1738...,
#   "total" => 45
# }
```

## 7. Test AI Anomaly Detection

Test the AI Detector for anomaly scoring:

```elixir
alias Flux.AI.Detector

# Record some baseline values
for value <- [100, 102, 98, 101, 99, 100, 103, 97, 100, 101] do
  Detector.record("test-pipeline", "response_time", value)
end

# Wait for async writes
:timer.sleep(50)

# Check the stats
{:ok, stats} = Detector.get_stats("test-pipeline", "response_time")
IO.inspect(stats)
# => %{count: 10, sum: 1001, min: 97, max: 103, ...}

# Score a normal value (should be low score)
{:ok, normal_score} = Detector.score("test-pipeline", %{"response_time" => 100}, ["response_time"])
IO.puts("Normal value score: #{normal_score}")
# => ~0.0

# Score an anomalous value (should be high score)
{:ok, anomaly_score} = Detector.score("test-pipeline", %{"response_time" => 500}, ["response_time"])
IO.puts("Anomaly score: #{anomaly_score}")
# => > 100 (very high z-score)

# Clean up
Detector.clear_pipeline("test-pipeline")
```

## 8. Test Pipeline with AI Step

Create a pipeline that includes anomaly detection:

```elixir
alias Flux.Pipelines

{:ok, ai_pipeline} = Pipelines.create_pipeline(%{
  name: "metrics-with-anomaly-detection",
  source_queue: "metrics.incoming",
  organization_id: org_id,
  status: "stopped",
  steps: %{
    "version" => "1.0",
    "steps" => [
      %{
        "id" => "detect-anomaly",
        "type" => "ai",
        "operation" => "anomaly_detect",
        "config" => %{
          "fields" => ["value", "latency"],
          "threshold" => 2.0,
          "pipeline_id" => "metrics-pipeline"
        }
      }
    ]
  }
})

# Start it
Manager.start_pipeline(ai_pipeline.id)

# Send metrics - first build up baseline
alias Flux.Pipeline.Producers.Memory

for _ <- 1..20 do
  Memory.push_message("metrics.incoming", %{
    "value" => 100 + :rand.uniform(10) - 5,
    "latency" => 50 + :rand.uniform(10) - 5
  })
  :timer.sleep(10)
end

# Now send an anomaly
Memory.push_message("metrics.incoming", %{
  "value" => 500,  # Way above normal
  "latency" => 50
})
```

Messages with anomalies will have an `_anomaly` field added with the score.

## 9. Test Individual Steps

### Map Step
```elixir
alias Flux.Pipeline.Steps.Map

data = %{"user" => %{"profile" => %{"name" => "Alice"}}}
config = %{"field" => "user.profile.name", "to" => "user_name"}

{:ok, result} = Map.execute(data, config)
# => %{..., "user_name" => "Alice"}
```

### Filter Step
```elixir
alias Flux.Pipeline.Steps.Filter

# Numeric comparison
data = %{"score" => 85}
{:ok, _} = Filter.execute(data, %{"field" => "score", "operator" => "gte", "value" => 80})

# String contains
data = %{"message" => "Hello world"}
{:ok, _} = Filter.execute(data, %{"field" => "message", "operator" => "contains", "value" => "world"})

# Regex match
data = %{"email" => "test@example.com"}
{:ok, _} = Filter.execute(data, %{"field" => "email", "operator" => "matches", "value" => "@example\\.com$"})
```

### Rename Step
```elixir
alias Flux.Pipeline.Steps.Rename

data = %{"old_key" => "value", "other" => "data"}
config = %{"from" => "old_key", "to" => "new_key"}

{:ok, result} = Rename.execute(data, config)
# => %{"new_key" => "value", "other" => "data"}
```

## 10. Stop and Clean Up

```elixir
# Stop the pipeline
Manager.stop_pipeline(pipeline.id)

# Verify it stopped
Manager.get_status(pipeline.id)
# => :stopped

# Delete the pipeline
Pipelines.delete_pipeline(pipeline)
```

## Running Automated Tests

Run the test suite for the new features:

```bash
# Run all iteration 3 tests
mix test test/flux/pipeline/ test/flux/ai/

# Run specific test file
mix test test/flux/pipeline/interpreter_test.exs

# Run with verbose output
mix test test/flux/pipeline/ --trace

# Run full precommit
mix precommit
```

## Troubleshooting

### Pipeline won't start
- Check if it's already running: `Manager.get_status(pipeline_id)`
- Check the logs for errors
- Verify the pipeline exists: `Pipelines.get_pipeline!(pipeline_id)`

### Messages not being processed
- Ensure you're using the correct source queue name
- Check that the pipeline status is `:running`
- Look for errors in the console/logs

### Lua script errors
- Test the script in isolation using `Script.execute/2`
- Check for syntax errors in your Lua code
- Ensure you're returning a table from `transform()`

### Anomaly detection not working
- Ensure you've recorded enough baseline values (at least 2)
- Check that field names match between your data and config
- Use `Detector.get_stats/2` to verify data is being recorded
