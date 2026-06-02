# Testing Iterations 1 & 2 (Archived)

> **Archived**: This QA checklist was used during initial development. See [developer_guide.md](../developer_guide.md) for current testing conventions and [operator_manual.md](../operator_manual.md) for Docker Compose setup.

## Prerequisites
Make sure Docker is installed and running.

---

## Option A: Full Docker Setup (Recommended)

Run the entire stack in Docker containers:

```bash
docker compose up --build
```

This starts:
- **App**: Phoenix server on `http://localhost:4000`
- **PostgreSQL**: Database on port `5432`
- **RabbitMQ**: Message queue on port `5672`, Management UI on `http://localhost:15672`

### Seed Data (Optional)
To create a test user, run seeds after the app starts:
```bash
docker compose exec app mix run priv/repo/seeds.exs
```

Test credentials: `admin@flux.dev` / `password1234`

---

## Option B: Local Development with Docker Services

Run only the database and RabbitMQ in Docker:

```bash
docker compose up -d db rabbitmq
```

Then run the app locally:
```bash
cd app
mix deps.get
mix ecto.setup   # creates DB, runs migrations, seeds
mix phx.server
```

---

## 1. Automated Unit Tests

Run the test suite to verify all functionality:
```bash
cd app
mix deps.get
mix test
```

Run specific test categories:
```bash
# Queue tests
mix test test/flux/queue/

# Worker tests
mix test test/flux/workers/

# API tests
mix test test/flux_web/controllers/api/
```

---

## 2. Visual Verification (Dashboard)

1. **Visit**: `http://localhost:4000`
2. **Register**: Create a new account at `/users/register`
3. **Dashboard**: After login, navigate to `/dashboard`

---

## 3. Webhook API Testing (Iteration 2)

Test the webhook endpoint with cURL:

### Successful Request
```bash
curl -X POST http://localhost:4000/api/webhooks/test \
  -H "Content-Type: application/json" \
  -H "X-API-Key: dev-api-key" \
  -d '{"event": "test.created", "data": {"id": 1}}'
```

Expected response (202 Accepted):
```json
{"status": "accepted", "message_id": "...", "queue": "webhooks.test"}
```

### With Correlation ID
```bash
curl -X POST http://localhost:4000/api/webhooks/github \
  -H "Content-Type: application/json" \
  -H "X-API-Key: dev-api-key" \
  -H "X-Correlation-ID: req-12345" \
  -d '{"action": "push", "repository": "flux"}'
```

### Missing API Key (401 Unauthorized)
```bash
curl -X POST http://localhost:4000/api/webhooks/test \
  -H "Content-Type: application/json" \
  -d '{"event": "test"}'
```

### Invalid API Key (401 Unauthorized)
```bash
curl -X POST http://localhost:4000/api/webhooks/test \
  -H "Content-Type: application/json" \
  -H "X-API-Key: wrong-key" \
  -d '{"event": "test"}'
```

---

## 4. RabbitMQ Management UI

Access the RabbitMQ management interface:
- **URL**: `http://localhost:15672`
- **Username**: `guest`
- **Password**: `guest`

In production mode, you can view:
- Exchanges: `flux.events`, `flux.events.dlx`
- Queues: `flux.events.dlq` (dead letter queue)
- Message rates and connection status

---

## 5. Run Precommit Checks

Before committing, run the full precommit suite:
```bash
cd app
mix precommit
```

This runs formatting, compilation checks, and tests.

---

## Docker Commands Reference

```bash
# Start all services
docker compose up --build

# Start in background
docker compose up -d

# View logs
docker compose logs -f app

# Stop all services
docker compose down

# Stop and remove volumes (fresh start)
docker compose down -v

# Run seeds in Docker
docker compose exec app mix run priv/repo/seeds.exs

# Run tests in Docker
docker compose exec app mix test

# Access IEx shell in Docker
docker compose exec app iex -S mix
```

---

## Environment Configuration

### Development API Key
The dev API key is configured in `config/dev.exs`:
```elixir
config :flux, FluxWeb.Plugs.ApiAuth, api_key: "dev-api-key"
```

### Docker Environment Variables
Set in `docker-compose.yml`:
- `MIX_ENV=dev`
- `POSTGRES_HOST=db`
- `RABBITMQ_HOST=rabbitmq`
