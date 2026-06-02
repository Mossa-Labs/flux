# Lua Scripting in Flux Pipelines

Flux supports custom Lua scripts for user-defined data transformations. This allows you to implement complex business logic that goes beyond the built-in native steps (map, filter, rename).

## Overview

Lua scripts execute in a sandboxed environment with restricted access to system resources. Each script must define a `transform` function that receives the data and returns the transformed result.

## Basic Structure

Every Lua script must define a `transform` function:

```lua
function transform(data)
  -- Your transformation logic here
  return data
end
```

The `data` parameter is a Lua table containing the message payload. You must return a table (which will be converted back to a map in Elixir).

## Pipeline Configuration

To use a Lua script in your pipeline, add a step with `type: "script"`:

```json
{
  "version": "1.0",
  "steps": [
    {
      "id": "custom-transform",
      "type": "script",
      "language": "lua",
      "code": "function transform(data)\n  data.processed = true\n  return data\nend",
      "timeout_ms": 5000
    }
  ]
}
```

### Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `code` | string | required | The Lua source code |
| `timeout_ms` | integer | 5000 | Maximum execution time in milliseconds |

## Examples

### 1. Adding Timestamps

Add a processing timestamp to each message:

```lua
function transform(data)
  data.processed_at = os.time()
  data.processed_date = os.date("%Y-%m-%d %H:%M:%S")
  return data
end
```

### 2. Conditional Field Mapping

Map different fields based on the event type:

```lua
function transform(data)
  if data.event_type == "user.created" then
    data.action = "create"
    data.entity = "user"
  elseif data.event_type == "user.updated" then
    data.action = "update"
    data.entity = "user"
  elseif data.event_type == "user.deleted" then
    data.action = "delete"
    data.entity = "user"
  end

  return data
end
```

### 3. Data Normalization

Normalize phone numbers and email addresses:

```lua
function transform(data)
  -- Normalize email to lowercase
  if data.email then
    data.email = string.lower(data.email)
  end

  -- Remove non-numeric characters from phone
  if data.phone then
    data.phone_normalized = string.gsub(data.phone, "[^0-9]", "")
  end

  return data
end
```

### 4. Calculating Derived Fields

Compute new fields from existing data:

```lua
function transform(data)
  -- Calculate total from line items
  if data.items then
    local total = 0
    for i, item in ipairs(data.items) do
      local item_total = (item.price or 0) * (item.quantity or 1)
      total = total + item_total
    end
    data.subtotal = total
    data.tax = total * 0.08
    data.total = total + data.tax
  end

  return data
end
```

### 5. String Manipulation

Extract and format string data:

```lua
function transform(data)
  -- Extract domain from email
  if data.email then
    local at_pos = string.find(data.email, "@")
    if at_pos then
      data.email_domain = string.sub(data.email, at_pos + 1)
    end
  end

  -- Create full name from parts
  if data.first_name and data.last_name then
    data.full_name = data.first_name .. " " .. data.last_name
  end

  -- Truncate long descriptions
  if data.description and string.len(data.description) > 100 then
    data.description_short = string.sub(data.description, 1, 97) .. "..."
  end

  return data
end
```

### 6. Data Enrichment with Lookups

Use lookup tables for data enrichment:

```lua
function transform(data)
  -- Country code to name mapping
  local countries = {
    US = "United States",
    CA = "Canada",
    GB = "United Kingdom",
    DE = "Germany",
    FR = "France",
    JP = "Japan",
    AU = "Australia"
  }

  if data.country_code then
    data.country_name = countries[data.country_code] or "Unknown"
  end

  -- Status code mapping
  local statuses = {
    [1] = "pending",
    [2] = "processing",
    [3] = "completed",
    [4] = "failed",
    [5] = "cancelled"
  }

  if data.status_code then
    data.status_name = statuses[data.status_code] or "unknown"
  end

  return data
end
```

### 7. JSON Path-like Field Extraction

Flatten nested structures:

```lua
function transform(data)
  -- Extract nested user info
  if data.payload and data.payload.user then
    local user = data.payload.user
    data.user_id = user.id
    data.user_email = user.email
    data.user_name = user.name
  end

  -- Extract nested address
  if data.payload and data.payload.address then
    local addr = data.payload.address
    data.address_line = addr.street .. ", " .. addr.city .. ", " .. addr.state .. " " .. addr.zip
  end

  return data
end
```

### 8. Data Validation and Flagging

Add validation flags for downstream processing:

```lua
function transform(data)
  data.validation = {}
  data.is_valid = true

  -- Check required fields
  if not data.email or data.email == "" then
    table.insert(data.validation, "missing_email")
    data.is_valid = false
  end

  if not data.user_id then
    table.insert(data.validation, "missing_user_id")
    data.is_valid = false
  end

  -- Validate email format (simple check)
  if data.email and not string.find(data.email, "@") then
    table.insert(data.validation, "invalid_email_format")
    data.is_valid = false
  end

  -- Check numeric ranges
  if data.amount and (data.amount < 0 or data.amount > 1000000) then
    table.insert(data.validation, "amount_out_of_range")
    data.is_valid = false
  end

  return data
end
```

### 9. Aggregating Array Data

Summarize array fields:

```lua
function transform(data)
  if data.events then
    data.event_count = #data.events

    -- Count by type
    local type_counts = {}
    for i, event in ipairs(data.events) do
      local t = event.type or "unknown"
      type_counts[t] = (type_counts[t] or 0) + 1
    end
    data.events_by_type = type_counts

    -- Get first and last event times
    if #data.events > 0 then
      data.first_event_at = data.events[1].timestamp
      data.last_event_at = data.events[#data.events].timestamp
    end
  end

  return data
end
```

### 10. Combining Multiple Transformations

A complete transformation pipeline in a single script:

```lua
function transform(data)
  -- Step 1: Normalize strings
  if data.email then
    data.email = string.lower(data.email)
  end

  -- Step 2: Add metadata
  data.processed_at = os.time()
  data.pipeline_version = "1.0"

  -- Step 3: Calculate derived fields
  if data.price and data.quantity then
    data.total = data.price * data.quantity
  end

  -- Step 4: Classify the record
  if data.total then
    if data.total >= 1000 then
      data.tier = "enterprise"
    elseif data.total >= 100 then
      data.tier = "business"
    else
      data.tier = "starter"
    end
  end

  -- Step 5: Clean up temporary fields
  data.internal_id = nil
  data.debug_info = nil

  return data
end
```

## Available Lua Functions

The following standard Lua libraries and functions are available:

### Safe Functions
- `string.*` - All string manipulation functions
- `table.*` - All table functions
- `math.*` - All math functions
- `os.time()` - Get current Unix timestamp
- `os.date()` - Format date/time strings
- `os.clock()` - CPU time used
- `os.difftime()` - Time difference calculation
- `tonumber()`, `tostring()` - Type conversion
- `type()` - Get variable type
- `pairs()`, `ipairs()` - Table iteration
- `next()` - Table traversal
- `select()` - Variable argument handling
- `unpack()` - Table unpacking
- `pcall()`, `xpcall()` - Protected calls
- `error()` - Raise errors
- `assert()` - Assertions

### Restricted Functions (Not Available)
For security reasons, the following are disabled:
- `io.*` - File I/O operations
- `file.*` - File handling
- `os.execute()` - System command execution
- `os.exit()` - Process termination
- `os.remove()` - File deletion
- `os.rename()` - File renaming
- `os.getenv()` - Environment variables
- `loadfile()`, `dofile()` - External file loading
- `require()` - Module loading
- `package.*` - Package management

## Error Handling

If your script encounters an error, the message will be marked as failed and sent to the dead letter queue (DLQ). Common errors include:

- **Timeout**: Script exceeded `timeout_ms`
- **Runtime Error**: Lua syntax or runtime errors
- **Type Error**: Returning non-table value from `transform`

Use `pcall` for graceful error handling within your script:

```lua
function transform(data)
  local success, result = pcall(function()
    -- Potentially risky operation
    return tonumber(data.value) * 2
  end)

  if success then
    data.doubled_value = result
  else
    data.parse_error = true
    data.doubled_value = 0
  end

  return data
end
```

## Performance Tips

1. **Keep scripts simple**: Complex scripts increase processing latency
2. **Avoid loops over large arrays**: Process data in batches if possible
3. **Use appropriate timeouts**: Set `timeout_ms` based on expected complexity
4. **Pre-compute lookup tables**: Define static tables outside the transform function
5. **Minimize string concatenation**: Use `table.concat` for joining many strings

## Testing Scripts

You can test Lua scripts in the Elixir console:

```elixir
# In iex -S mix
alias Flux.Pipeline.Steps.Script

data = %{"name" => "John", "email" => "JOHN@EXAMPLE.COM"}
config = %{
  "code" => """
  function transform(data)
    data.email = string.lower(data.email)
    data.greeting = "Hello, " .. data.name
    return data
  end
  """,
  "timeout_ms" => 5000
}

{:ok, result} = Script.execute(data, config)
# => %{"name" => "John", "email" => "john@example.com", "greeting" => "Hello, John"}
```
