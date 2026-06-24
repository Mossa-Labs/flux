# Connecting to external databases

The [MySQL sink](mysql.md) and the **external** mode of the
[Postgres sink](../user_guide.md) connect *outbound* from the Flux server to a
database **you** run. Because the database is outside Flux, a sink can be saved
with valid credentials and still fail to deliver if the network path is blocked.
This page covers the networking you need to get right.

> **Tip:** Use **Test Connection** on the sink form before attaching the sink to a
> pipeline. It performs the same outbound connection delivery uses, so it surfaces
> a blocked network or wrong port immediately — without waiting for events to flow.

## Port

The `database_url` must use the port your database actually listens on:

| Database | Default port |
| --- | --- |
| MySQL | `3306` |
| PostgreSQL | `5432` |

Managed databases and proxies often differ — e.g. an RDS Proxy, a PgBouncer pool,
or a non-standard port behind a load balancer. Use the real listening port, not
the default, in the URL: `mysql://user:pass@host:6033/db`.

## Source IP / egress allowlisting

Flux **dials out** to your database. Your database's firewall sees the connection
arriving from the **Flux server's egress IP address**, and that is the address you
must allowlist — not the database's own IP, and not the Flux instance's private IP.

In typical cloud deployments Flux sits in a private subnet behind a **NAT
gateway**, so the source address your database sees is the **NAT gateway's
Elastic/static IP**, which is shared by everything in that subnet. Allowlist that
address in:

- the database's **security group** / firewall (e.g. AWS RDS inbound rules),
- the database's host-based rules where applicable (PostgreSQL `pg_hba.conf`),
- any **VPC peering**, **PrivateLink**, or VPN route between the two networks.

### Finding the egress IP

- **AWS (NAT gateway):** the Elastic IP attached to the NAT gateway in the VPC
  console — this is what databases outside the VPC will see.
- **From the Flux host directly:** `curl ifconfig.me` (or `curl https://api.ipify.org`)
  returns the public address Flux egresses from.

If Flux runs on multiple nodes across subnets, each may egress from a different
NAT gateway — allowlist **all** of them.

## Diagnosing failures

The error tells you which layer failed:

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Connection **timeout** | Network/firewall — packets never reach the DB | Allowlist the egress IP; check the port and security groups |
| **Connection refused** | Reached the host, nothing listening on that port | Fix the port; confirm the DB is up and bound to a reachable interface |
| **Authentication / access denied** | Network is fine; credentials or grants are wrong | Fix `user`/`password`; grant the user access **from the Flux source host** |
| **TLS / SSL** errors | Server requires (or rejects) TLS | Toggle `ssl` to match the server's requirement |

A timeout almost always means networking; an auth error almost always means the
network is fine and the problem is credentials or grants.
