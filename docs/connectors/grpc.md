# gRPC Connector (Source)

gRPC is an **Enterprise** connector available as a **source**. It runs in one of
two modes, and in both it lands each message onto Flux's internal queue, which
your pipeline then consumes: *RPC → transform / detect → sink*.

- **Server mode:** Flux hosts a small, fixed ingest service
  (`flux.ingest.v1.Ingest`). Your services call it, unary or as a bidirectional
  stream, and every message they send becomes a pipeline event.
- **Client mode:** Flux dials **your** gRPC server and consumes a server-streaming
  or bidirectional-streaming RPC, decoding each response to JSON.

> **Enterprise feature.** On the Community and Pro editions the gRPC source is
> gated: the type appears in the UI marked *Enterprise* and any saved config is
> rejected with an upgrade prompt. The real adapter ships in the Flux Enterprise
> edition. Activate an Enterprise license to enable it. See
> [pricing](https://fluxdata.tech/pricing.html).

## Server mode

### The ingest service

Server mode always speaks this contract. Generate client stubs from it with your
language's gRPC tooling.

```proto
syntax = "proto3";

package flux.ingest.v1;

import "google/protobuf/struct.proto";

service Ingest {
  // One message, one acknowledgement.
  rpc Publish(PublishRequest) returns (PublishResponse);

  // Many messages over one stream. Flux returns one PublishResponse per
  // request, in order, after the message is safely enqueued.
  rpc PublishStream(stream PublishRequest) returns (stream PublishResponse);
}

message PublishRequest {
  // Caller-chosen ID, echoed in the response and passed to the pipeline as
  // metadata (use it for downstream de-duplication).
  string message_id = 1;

  oneof payload {
    google.protobuf.Struct json = 2;  // structured payload, becomes the event map
    bytes raw = 3;                    // opaque bytes, see "Payloads" below
  }

  string content_type = 4;            // optional, describes `raw`
  map<string, string> attributes = 5; // passed through as event metadata
}

message PublishResponse {
  enum Status {
    STATUS_UNSPECIFIED = 0;
    ACCEPTED = 1;
    REJECTED = 2;
  }

  string message_id = 1;
  Status status = 2;
  string error = 3;  // set when status is REJECTED
}
```

**Payloads.** A `json` payload becomes the event map as-is. It travels as a
`google.protobuf.Struct`, whose numbers are all doubles, so `42` arrives as
`42.0`; send the JSON as `raw` bytes to keep integers. A `raw` payload is
parsed as JSON: an object becomes the event map, and any other JSON value
arrives as `{"value": ...}`. Bytes that aren't JSON arrive as
`{"raw": "<base64>"}`. Each event's metadata carries a `grpc` map with the
source ID, `message_id`, `content_type`, `attributes`, and the caller's
certificate subjects.

The listener also serves [gRPC server reflection](https://grpc.io/docs/guides/reflection/),
so tools such as `grpcurl` can call it without a copy of the `.proto`.

### Routing: `x-flux-source`

One gRPC listener serves every server-mode source on a node. Each call names its
target source in the **`x-flux-source`** metadata header, set to the **source's
ID**. A call without the header fails with `INVALID_ARGUMENT`, a call naming an
unknown (or client-mode) source fails with `NOT_FOUND`, and a call to a disabled
source fails with `FAILED_PRECONDITION`.

Messages land on the internal queue `grpc.<channel>`, where `channel` is set on
the source. Point the pipeline that should process them at that queue.

### Deployment settings

The listener is configured per deployment, not per source. It starts only when an
Enterprise license is active **and** `FLUX_GRPC_PORT` is set.

| Variable | Required | Description |
| --- | --- | --- |
| `FLUX_GRPC_PORT` | yes | Port the gRPC listener binds on every node (e.g. `50051`) |
| `FLUX_GRPC_TLS_CERTFILE` | yes | PEM server certificate presented to callers |
| `FLUX_GRPC_TLS_KEYFILE` | yes | PEM private key for the server certificate |
| `FLUX_GRPC_CLIENT_CA_FILE` | for mTLS | PEM CA bundle used to verify client certificates; required by any source using `mtls` or `mtls_bearer` |

The listener only accepts TLS. Plaintext (h2c) is not offered in server mode.

### Auth matrix

| `auth_mode` | Description |
| --- | --- |
| `mtls` (default) | Caller presents a client certificate signed by `FLUX_GRPC_CLIENT_CA_FILE` whose CN or a SAN is in `allowed_client_subjects` |
| `bearer` | Caller sends `authorization: Bearer <bearer_token>` metadata |
| `mtls_bearer` | Both checks must pass |

`allowed_client_subjects` is required for the mTLS modes. Without it, any
certificate the deployment CA signed could publish into the source. Failed checks
return `UNAUTHENTICATED` (missing or invalid credentials) or `PERMISSION_DENIED`
(valid certificate, subject not allowed). The bearer token is masked
(`[REDACTED]`) when configuration leaves the system (e.g. API reads).

### Server-mode configuration

| Field | Required | Description |
| --- | --- | --- |
| `mode` | no | `server` (default) |
| `channel` | yes | Names the internal queue the source feeds: `grpc.<channel>` |
| `auth_mode` | no | One of the auth modes above (default `mtls`) |
| `allowed_client_subjects` | conditional | List of allowed certificate CNs / SANs; required for `mtls` and `mtls_bearer` |
| `bearer_token` | conditional | Shared secret; required for `bearer` and `mtls_bearer` |
| `max_message_bytes` | no | Largest accepted request message (default `4194304`, 4 MiB) |

```json
{
  "type": "grpc",
  "mode": "server",
  "channel": "orders",
  "auth_mode": "mtls",
  "allowed_client_subjects": ["orders-service"]
}
```

Calling it with [`grpcurl`](https://github.com/fullstorydev/grpcurl):

```sh
grpcurl \
  -cacert ca.pem -cert orders-service.pem -key orders-service-key.pem \
  -H 'x-flux-source: <source-id>' \
  -d '{"message_id": "evt-1", "json": {"order_id": 42, "total": 19.5}}' \
  flux.example.com:50051 flux.ingest.v1.Ingest/Publish
```

### Status codes

| Code | When |
| --- | --- |
| `OK` + `ACCEPTED` | The message was enqueued |
| `OK` + `REJECTED` | The message was refused (e.g. undecodable payload); the stream stays open |
| `INVALID_ARGUMENT` | The call has no `x-flux-source` header |
| `NOT_FOUND` / `FAILED_PRECONDITION` | Unknown or disabled source |
| `UNAUTHENTICATED` / `PERMISSION_DENIED` | Auth failed (see the auth matrix) |
| `RESOURCE_EXHAUSTED` | The organization is over its usage quota, or the message exceeds `max_message_bytes` |
| `DEADLINE_EXCEEDED` | The caller's deadline passed before the message was enqueued |
| `UNAVAILABLE` | The node is shutting down, or the internal queue is unavailable; retry (the load balancer routes to another node) |

## Client mode

In client mode Flux opens one long-lived call to `method` on `endpoint` and
publishes every response message. Only one node in a cluster runs a given
client-mode source at a time.

### Message schemas

Flux needs the service's message definitions to encode `request` and decode
responses. Set `schema_source` to choose where they come from:

- `reflection` (default): Flux asks the server through the
  [gRPC server reflection](https://grpc.io/docs/guides/reflection/) service (v1,
  falling back to v1alpha). The server must have reflection enabled.
- `descriptor`: you supply a descriptor set in `descriptor_set`. Build it with
  `protoc` and base64-encode the output:

  ```sh
  protoc --include_imports --descriptor_set_out=telemetry.protoset telemetry.proto
  base64 < telemetry.protoset
  ```

  `--include_imports` matters: without it, imported types such as
  `google.protobuf.Timestamp` cannot be resolved.

Validation and **Test connection** resolve `method` against the schema and check
that `rpc_type` matches its streaming shape. Responses are decoded with the
proto3 JSON mapping, with a few changes that suit pipelines:

- Field names stay as written in the `.proto` (`device_id`, not `deviceId`).
- 64-bit integers decode to numbers, not strings.
- Fields without presence always appear, holding their default value. Unset
  message fields, `oneof` members and `optional` fields are left out.

Enums decode to their names, `Timestamp` / `Duration` to strings, `bytes` to
base64, and `Struct` / `Value` to plain JSON. A response that doesn't match the
schema still lands, as `{"raw": "<base64>"}` with a `decode_error` in its
metadata. `request` accepts either spelling of field names.

### Client-mode configuration

| Field | Required | Description |
| --- | --- | --- |
| `mode` | yes | `client` |
| `channel` | no | Names the internal queue the source feeds, `grpc.<channel>`; defaults to one derived from `method` |
| `endpoint` | yes | `host:port` of the gRPC server |
| `method` | yes | Fully-qualified RPC path, e.g. `/telemetry.v1.Telemetry/StreamReadings` |
| `rpc_type` | no | `server_streaming` (default) or `bidi` |
| `request` | no | JSON request message sent when the stream opens (default `{}`) |
| `schema_source` | no | `reflection` (default) or `descriptor` |
| `descriptor_set` | conditional | Base64 `.protoset`; required when `schema_source` is `descriptor` |
| `transport_security` | no | `tls` (default), `mtls`, or `none` (plaintext h2c) |
| `ca_cert` | no | PEM CA bundle that verifies the server; defaults to the system trust store |
| `client_cert` / `client_key` | conditional | PEM client certificate and key; required for `mtls` |
| `bearer_token` | no | Sent as `authorization: Bearer <token>` metadata |
| `metadata` | no | Map of extra request metadata (string values) |
| `deadline_ms` | no | Time allowed to connect and receive the first message (default `10000`) |
| `idle_timeout_ms` | no | Reconnect when no message arrives for this long (default: never) |

`bearer_token` and `client_key` are masked (`[REDACTED]`) when configuration
leaves the system.

```json
{
  "type": "grpc",
  "mode": "client",
  "channel": "telemetry",
  "endpoint": "telemetry.example.com:443",
  "method": "/telemetry.v1.Telemetry/StreamReadings",
  "rpc_type": "server_streaming",
  "request": {"device_id": "line-4"},
  "schema_source": "reflection",
  "transport_security": "tls",
  "bearer_token": "…"
}
```

For `bidi`, Flux sends `request` when the stream opens and keeps its side of the
stream open. It does not send further messages.

## Delivery semantics

- **Server mode: at-least-once.** Flux acknowledges a message (`ACCEPTED`) only
  **after** it is enqueued. A caller that retries messages it never saw
  acknowledged can therefore deliver duplicates. Use `message_id` downstream to
  de-duplicate.
- **Client mode: at-most-once across reconnects.** Flux publishes each response
  before reading the next, so backpressure flows to the server through HTTP/2
  flow control. A generic gRPC stream has no resume cursor, though. If the
  connection drops, messages the server sent but Flux had not yet received are
  lost, and the reconnected call starts from whatever the server sends next.
- **Ordering** is preserved per stream in both modes.
- **Shutdown.** Server mode stops accepting new calls, finishes the in-flight
  message on each stream, then ends open streams with `UNAVAILABLE`. Client mode
  finishes publishing the current message and cancels the call.

## Networking & firewall

**Server mode is inbound.** Every Flux node listens on `FLUX_GRPC_PORT`, so expose
that port through your load balancer:

- Use an **L4 (TCP) load balancer with TLS passthrough**, so Flux terminates TLS
  and can check client certificates. An L7 balancer that terminates TLS hides the
  client certificate from Flux and breaks `mtls`.
- If you must terminate TLS at an L7 proxy, it has to speak HTTP/2 to Flux end to
  end, and only `bearer` auth will work.
- On Kubernetes, add the port to the Flux `Service` (e.g. `name: grpc`,
  `port: 50051`, `appProtocol: grpc`) and to any `NetworkPolicy`.
- gRPC connections are long-lived. Balancing happens per connection, not per
  call, so callers should reconnect periodically (or set a max connection age) to
  spread load after scaling out.

**Client mode is outbound.** Flux dials `endpoint` from the node running the
source, the same egress model as
[external databases](external-databases.md). Allow that node's egress IP
(usually a NAT gateway's static IP) on the server's firewall. Use **Test
connection** to verify reachability, TLS, auth and schema resolution up front.

## Not yet supported

- **ALTS** (Google's Application Layer Transport Security) for GCP-to-GCP
  traffic. Use mTLS instead.
- Resuming a client-mode stream from a cursor after a reconnect.
