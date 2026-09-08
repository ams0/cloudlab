# n8n

Powerful workflow automation platform and self-hosted alternative to Zapier/Make. This is one of the most complex deployments in the cluster, featuring a multi-tier queue-based architecture.

## Resources

- `namespace.yaml` - Namespace definition
- `n8n-ocirepo.yaml` - OCI chart repository source (n8n)
- `n8n-database-helmrelease.yaml` - CNPG PostgreSQL 18 cluster
- `n8n-pvc.yaml` - 10Gi PVC (local-path) for n8n data
- `n8n-helmrelease.yaml` - Flux HelmRelease (app)
- `n8n-httproute.yaml` - Gateway API HTTPRoute

## Architecture

n8n runs in **queue mode** with three components:

1. **Main server** - Handles the UI, webhook endpoints, and the workflow editor. Accepts incoming workflow triggers and enqueues jobs.
2. **Worker** (1 replica, 10 concurrent jobs) - Executes workflows picked from the Bull queue. Offloads execution from the main server, enabling horizontal scaling.
3. **Valkey** - In-chart Valkey (a Redis fork) powers the Bull message queue that distributes jobs between main and workers.

A standalone `redis-n8n` HelmRelease used to be deployed alongside this, with its own 5Gi PVC. Nothing ever connected to it — the queue points at `n8n-n8n-valkey` — so it was removed. Do not add it back without also repointing `config.queue.bull.redis.host`.

## HelmRelease Values

| Key | Value | Notes |
|-----|-------|-------|
| `image.tag` | `2.15.0` | Renovate auto-update enabled |
| `config.executions.mode` | `queue` | Enables worker-based execution (not "regular") |
| `config.bull.redis.host` | `n8n-n8n-valkey` | Queue backend |
| `WEBHOOK_URL` | `https://n8n.vps.kubespaces.cloud` | External webhook endpoint |
| `N8N_PROXY_HOPS` | `1` | Behind Istio gateway |
| `OFFLOAD_MANUAL_EXECUTIONS_TO_WORKERS` | `true` | Even manual test runs go to workers |
| `N8N_RUNNERS_DISABLED` (worker) | `true` | Workers don't spawn sub-runners |
| Security context | non-root, UID 1000 | Runs as unprivileged user |
| Resource limits | 1 CPU / 1Gi memory | Requests: 100m CPU / 256Mi memory |

## Database

**CNPG PostgreSQL 18** (`n8n-database`) - standalone, 1 instance.

n8n stores workflow definitions, encrypted credentials, execution history, and user data in PostgreSQL. The queue-based architecture requires a shared database accessible by both the main server and worker pods. DB host: `n8n-n8n-database-cluster-rw`, password from CNPG-managed secret.

## Storage

**n8n-pvc: 10Gi local-path** - Stores binary data such as uploaded files, custom node packages, and encryption keys.

## Routing

| Hostname | Route |
|----------|-------|
| `n8n.vps.kubespaces.cloud` | HTTPRoute to n8n main server |

References the shared Istio gateway in `istio-system`.
