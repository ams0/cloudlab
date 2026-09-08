# Renovate Operator

[mogenius/renovate-operator](https://github.com/mogenius/renovate-operator) — runs
[Renovate](https://docs.renovatebot.com/) in-cluster with CRD-based scheduling,
parallel execution, auto-discovery and a web UI, instead of the hosted Mend app.

UI: `renovate.vps.kubespaces.cloud`

## Resources

- `namespace.yaml` — namespace
- `renovate-operator-ocirepository.yaml` — OCI chart source (`ghcr.io/mogenius/helm-charts`)
- `renovate-operator-helmrelease.yaml` — Flux HelmRelease
- `renovate-operator-httproute.yaml` — Gateway API HTTPRoute

No PVC: log storage is `disabled` and sessions are held in-process, so there is
no state to preserve. Enabling `config.logStorage.mode: valkey` or `s3` would
change that.

## Design decisions

**`fullnameOverride: renovate-operator`.** The chart's fullname helper is an
unconditional `<release>-<chart>` — no "does the release already contain the
chart name" check. Flux names the release `<targetNamespace>-<HelmRelease>`, so
without the override every object would be called
`renovate-operator-renovate-operator-renovate-operator`.

**`crd.mode: template`.** The chart defaults to `hook`, which runs a Job pulling
`registry.k8s.io/kubectl` to apply the CRDs. `template` renders them as ordinary
chart resources that Helm and Flux both track — one less moving part, and no
image pull on every install/upgrade. Note the CRDs are then removed on uninstall.

**`route.enabled: false`.** The chart can emit its own HTTPRoute, but routing is
kept in a separate file here like every other app, so the hostname and gateway
wiring live in one predictable place.

**`valkey.enabled: false` with `replicaCount: 1`.** Valkey exists to share
sessions across replicas. With one replica it would be a second pod on a
single-node cluster for nothing. Sessions do not survive a pod restart.

## Authentication — read this before exposing it further

The operator ships OIDC and GitHub OAuth support, and **both are off here**.
From the chart's own docs on `authorization.enabled`:

> Has no effect when no authentication provider is configured, since every
> request is an admin in that case.

So anyone who reaches the UI can trigger, cancel and inspect Renovate runs. The
public hostname is therefore behind Traefik's `dashboard-auth` basicAuth
middleware (`ingress/traefik/dynamic.yml`) as a stopgap.

The proper fix is OIDC against the Keycloak already running in this cluster:
set `auth.oidc.enabled`, `issuerUrl` to
`https://auth.vps.kubespaces.cloud/realms/<realm>`, a `clientId`, and
`auth.oidc.existingSecret` for the client secret. Keycloak needs `additionalScopes: ["groups"]`
to emit group claims. Once that is in place the basicAuth middleware can be
dropped from the router.

## Running Renovate

Deploying the operator does not update anything on its own. A `RenovateJob` CR
is needed, plus a platform token (for this repo, a GitHub PAT) supplied as a
secret. The operator watches cluster-wide (`rbac.ownNamespaceOnly: false`), so
RenovateJobs may live in any namespace.

Note this repo is *already* covered by hosted Renovate via `renovate.json`.
Running both against the same repo would produce duplicate PRs — pick one.
