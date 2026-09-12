# Twenty

[Twenty](https://twenty.com) — open-source CRM. Server + worker, CNPG PostgreSQL,
in-chart Redis.

UI: `crm.vps.kubespaces.cloud`

## Resources

- `namespace.yaml` — namespace
- `twenty-db-helmrelease.yaml` — CNPG PostgreSQL 18 cluster
- `twenty-pvc.yaml` — 10Gi PVC (local-path) for local file storage
- `twenty-helmrelease.yaml` — Flux HelmRelease (chart vendored at `charts/twenty`)
- `twenty-httproute.yaml` — Gateway API HTTPRoute

## Why the chart is vendored

Twenty publishes **no** Helm chart to any registry — not Docker Hub, not GHCR,
not a `helm repo`. The only official chart lives inside the monorepo at
`packages/twenty-docker/helm/twenty`, and that repo is **1.8 GB**, which is far
too heavy to pull through a Flux `GitRepository` on this single node (the Garage
pattern would otherwise apply).

So the chart is vendored into `charts/twenty/` and referenced through the
`flux-system` GitRepository that already tracks this repo:

```yaml
chart: ./charts/twenty
sourceRef:
  kind: GitRepository
  name: flux-system
```

**To update it**, re-copy `packages/twenty-docker/helm/twenty` from
`twentyhq/twenty@main` over `charts/twenty/` and re-render before committing:

```bash
helm template twenty-twenty ./charts/twenty -n twenty -f <values>
```

Note the upstream `Chart.yaml` says `appVersion: v1.14.0` while the app is on
v2.39.x — that field is simply not kept up to date. The image tag is pinned
explicitly in the HelmRelease and tracked by Renovate.

## Design decisions

**CNPG instead of the bundled database.** The chart defaults to
`twentycrm/twenty-postgres-spilo:3.3-p2`, and **that tag does not exist** — the
registry returns `MANIFEST_UNKNOWN`, and that image has had no build since
March 2025. Beyond being broken it is also unnecessary: the Spilo image exists
only to supply `mysql_fdw` and the Supabase `wrappers` extensions for Twenty's
remote-objects feature, which is gated behind `IS_FDW_ENABLED` and which
upstream describes in `setup-db.ts` as "We paused the work on FDW".

Core Twenty needs only `uuid-ossp`, `unaccent` and `citext`. All three are
*trusted* extensions in PG13+, so the database owner can create them without
superuser — verified against CNPG PG 18.6 by creating them, plus the `core`
schema and the `unaccent_immutable` function, as a non-superuser owner.

**Password is not url-encoded by the chart.** The external-DB path builds
`postgres://user:$(DB_PASSWORD)@host:port/db` with no `urlquery` on the
password. This is safe here because CNPG generates 64-character alphanumeric
passwords. It would break with a hand-set password containing `@`, `/` or `:`.

**In-chart Redis is kept.** `redis/redis-stack-server` is multi-arch and runs on
this arm64 host. Persistence is off — it only backs the job queue.

**`SERVER_URL` is set explicitly.** The chart normally derives it from the
ingress host, and the ingress is disabled here in favour of an HTTPRoute, so
without it Twenty would generate links against the wrong origin.

## APP_SECRET

`APP_SECRET` comes from the `tokens` Secret, which the chart generates on first
install. Its helper does a `lookup` of the existing Secret before generating, so
it is stable across upgrades — but it would be regenerated if the Secret or the
namespace were deleted, and **any data encrypted under the old value becomes
unreadable**. Back it up:

```bash
kubectl get secret tokens -n twenty -o jsonpath='{.data.accessToken}' | base64 -d
```

## First run

There is no seeded admin. Visit the URL and sign up; the first account becomes
the workspace owner. `SIGN_IN_PREFILLED` is `false` so no demo credentials are
offered.
