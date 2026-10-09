# Buzz

[block/buzz](https://github.com/block/buzz) — self-hosted team communication
(chat, huddles, git hosting) built on the Nostr protocol. The server component
is `buzz-relay`, a Rust binary.

- URL: `https://buzz.vps.kubespaces.cloud` (clients dial `wss://buzz.vps.kubespaces.cloud`)
- Chart: `oci://ghcr.io/block/buzz/charts/buzz` **0.1.11** (appVersion 0.1.0)
- Image: `ghcr.io/block/buzz:0.1.0` — multi-arch, arm64 ✓

No Helm chart had to be written: Buzz publishes an official one as an OCI
artifact. The source repo is ~600MB, so the chart is pulled as an OCIRepository
rather than built from a GitRepository.

## Authentication — not Keycloak

Buzz does **not** use OIDC. Identity is a Nostr keypair (NIP-01 / NIP-42 /
NIP-98): you log in by holding a private key, and the relay authorises by pubkey.
Keycloak appears in the upstream repo only as dev scaffolding (`start-dev`,
`KC_DB: dev-mem`) for unrelated demos, so it is not wired up here.

`relay.requireRelayMembership` is left at its default `true`, which keeps the
relay closed: only the owner and members they invite can connect. `ownerPubkey`
in the HelmRelease is the operator identity — the admin account.

Two **distinct** keypairs are in play:

| Key | Where | Purpose |
|-----|-------|---------|
| Owner | `ownerPubkey` (public, in Git) | The human admin identity. Private key held by the operator, never in the cluster. |
| Relay identity | `BUZZ_RELAY_PRIVATE_KEY` (vault) | The relay's *own* Nostr identity. Rotating it changes who the relay is, not just a credential. |

## Dependencies

| Need | How it is met |
|------|---------------|
| PostgreSQL | CNPG `Cluster` (`buzz-database-cluster`), per repo convention |
| Object storage | `buzz-silo` Deployment in-namespace (see below) |
| Redis | **Not deployed.** Only needed to fan out buzz-pubsub across pods; the chart marks `REDIS_URL` optional at `replicaCount: 1`. |

### Object storage is mandatory

Buzz keeps media *and git refs/objects* in an S3 bucket — each git request
hydrates an ephemeral repo from the bucket, and writer serialisation is an
object-store pointer CAS. The relay runs a startup S3 conformance probe and
**exits** if the bucket is unreachable, so storage is not optional.

The chart ships a bundled MinIO "quickstart", but it hard-fails when combined
with `secrets.existingSecret` — it insists on autogenerating credentials into a
chart-managed Secret, which the chart's own comments call "not GitOps-safe".
Since vault-backed secrets are the convention here, `buzz-silo.yaml` reproduces
that same topology explicitly with credentials we control. It uses the exact
`pgsty/silo` images and digests the upstream chart pins (a maintained MinIO fork
with public arm64 builds).

The conformance probe does **not** create the bucket, and the chart's
`wait-for-bucket` init container only renders for the bundled MinIO — so the
HelmRelease supplies an equivalent via `extraInitContainers`. It runs
`mc mb --ignore-existing`, which both creates the bucket on first boot and is
safe to re-run on every restart. A `Job` was deliberately avoided: its spec is
immutable, so any later edit would wedge Flux.

## The DATABASE_URL exception

Every other app here reads discrete `host`/`user`/`password` keys from the
secret CNPG generates. Buzz wants one composed `DATABASE_URL`, and CNPG normally
invents the owner password itself — which Ansible could not then embed in that
URL. So the owner credentials are created in `roles/flux` as `buzz-pg-app`
(type `kubernetes.io/basic-auth`) and the Cluster is pointed at them via
`cluster.initdb.secret.name`. Both sides then agree by construction.

## Secrets

`buzz-relay-env` (namespace `buzz`, created by `roles/flux`) is the single
Secret the relay reads, via `secrets.existingSecret`:

| Key | From vault |
|-----|-----------|
| `DATABASE_URL` | composed from `vault_buzz_pg_password` |
| `BUZZ_RELAY_PRIVATE_KEY` | `vault_buzz_relay_private_key` |
| `BUZZ_GIT_HOOK_HMAC_SECRET` | `vault_buzz_git_hook_hmac_secret` |
| `BUZZ_S3_ACCESS_KEY` | `vault_buzz_s3_access_key` |
| `BUZZ_S3_SECRET_KEY` | `vault_buzz_s3_secret_key` |

The same S3 keys are what `buzz-silo` serves as its root credentials.

## Single-node notes

- `buzz-silo` uses `strategy: Recreate` — a surging replica could never bind the
  ReadWriteOnce `local-path` volume.
- `persistence.git` is **scratch only** (5Gi). Refs and objects live in the
  bucket and repo-name uniqueness lives in Postgres, so nothing on that volume
  is authoritative.
- `git.packCacheMaxBytes`/`packCacheVolumeSize` are trimmed from the chart
  defaults (5GiB / 7Gi) to suit one shared ARM64 node.
