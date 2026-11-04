# Connectors

Sources bring data into a pipeline. Sinks deliver it. Community connectors work
in every build. Pro and Enterprise connectors appear in the Community build
marked with their edition, but saving one there shows an upgrade prompt. The
connectors themselves ship in the Flux Pro / Enterprise edition and run with an
active license for that edition (see
[pricing](https://fluxdata.tech/pricing.html)).

## Sources

| Connector | Edition | Notes |
| --- | --- | --- |
| Webhook | Community | Built in. See the [user guide](../user_guide.md). |
| Scheduled poll | Community | Built in. See the [user guide](../user_guide.md). |
| Internal queue | Community | Built in. See the [user guide](../user_guide.md). |
| [Kafka](kafka.md) | Pro | Also a sink. |
| [MQTT](mqtt.md) | Pro | |
| [Amazon SQS](sqs.md) | Pro | |
| [Amazon Kinesis](kinesis.md) | Pro | Polling or Enhanced Fan-Out. |
| [Google Pub/Sub](pubsub.md) | Pro | |
| [RabbitMQ (external)](rabbitmq-external.md) | Pro | |
| [SFTP](sftp.md) | Pro | |
| [gRPC](grpc.md) | Enterprise | Server mode (ingest listener) or client mode (server stream). |

## Sinks

| Connector | Edition | Notes |
| --- | --- | --- |
| HTTP | Community | Built in. See the [operator manual](../operator_manual.md#http-sink). |
| PostgreSQL | Community | Built in. See the [operator manual](../operator_manual.md#postgres-sink). |
| [MySQL](mysql.md) | Community | |
| [Parquet file](parquet.md) | Community | |
| [Email](email.md) | Community | |
| [S3 / cloud storage](s3.md) | Pro | |
| [Google Cloud Storage](gcs.md) | Pro | |
| [BigQuery](bigquery.md) | Pro | |
| [Kafka](kafka.md) | Pro | Also a source. |
| [Redis](redis.md) | Pro | |
| [MongoDB](mongodb.md) | Pro | |
| [Amazon DynamoDB](dynamodb.md) | Pro | |
| [Apache Cassandra](cassandra.md) | Pro | Includes ScyllaDB and Amazon Keyspaces. |
| [Slack](slack.md) | Pro | Also an alert channel. |
| [PagerDuty](pagerduty.md) | Enterprise | Also an alert channel. |

Snowflake is a Pro sink without a page here yet.

## Related

- [Connecting to external databases](external-databases.md): networking and
  credentials for database sinks.
- [Server AWS Credentials](../operator_manual.md#server-aws-credentials): how
  operators control whether AWS connectors may use the server's own identity.
