# Postiz

[gitroomhq/postiz-app](https://github.com/gitroomhq/postiz-app) (AGPL-3.0) — a
social media scheduler, at https://postiz.vps.kubespaces.cloud.

## Resources

| File | What |
|---|---|
| `postiz-deployment.yaml` | The app: one container, nginx `:5000` → frontend `:4200` + backend `:3000` + Temporal workers, under pm2 |
| `postiz-db-helmrelease.yaml` | CNPG Postgres `postiz` (2Gi); app reads `postiz-postiz-database-cluster-app` → `uri` |
| `postiz-temporal.yaml` | Temporal (`temporal server start-dev`, SQLite on `temporal-pvc`) at `temporal:7233` |
| `postiz-redis.yaml` | Redis 7, no persistence |
| `postiz-pvc.yaml` | `postiz-pvc` (5Gi: `/uploads`, `/config` subPaths) and `temporal-pvc` (2Gi) |
| `postiz-httproute.yaml` | `postiz.vps.kubespaces.cloud`; Traefik router `postiz` in `ingress/traefik/dynamic.yml` |

Keycloak client: `gitops/keycloak-resources/postiz-client.yaml`. Secrets
(`postiz/postiz-secrets`: `jwtSecret`, `oidcClientSecret`; and
`keycloak-operator/postiz-oidc`) are created by `roles/flux` from
`vault_postiz_jwt_secret` and `vault_postiz_oidc_client_secret`.

## Design decisions

| Decision | Why |
|---|---|
| **Raw manifests, not the Helm chart** | `gitroomhq/postiz-helmchart` was last released in January 2025, before Postiz moved scheduling to Temporal. It no longer matches the app. |
| **Temporal as the single-binary dev server with SQLite** | Upstream's compose runs `temporalio/auto-setup` with its own Postgres and Elasticsearch (about 1.5 GiB more RAM). For one user scheduling a handful of posts that is not worth it. It is persistent (SQLite on a PVC) and supports the custom search attributes Postiz registers at boot (`organizationId`, `postId`). Move to the Temporal Helm chart if this becomes multi-user. |
| `DISABLE_REGISTRATION=true` from day one | Postiz still lets the **first** account register (empty org table), then closes sign-up. Keycloak logins (`POSTIZ_GENERIC_OAUTH`) can always create accounts, and the realm itself is closed. |
| Keycloak as generic OAuth | Postiz reads `email` and `sub` from userinfo, and redirects to `FRONTEND_URL/settings`, which is the registered redirect URI. |
| Image pinned (`v2.26.0`), `Recreate` | Single node, RWO volume; upstream compose tracks `latest`. |
| Requests 50m CPU / 768Mi | The node's CPU *requests* were ~93% allocated at deploy time; the app needs memory, not reserved CPU. |

## Social networks

Each network (X, LinkedIn, Mastodon, …) needs its own developer app and the
matching `*_CLIENT_ID`/`*_CLIENT_SECRET` env vars (see upstream
`docker-compose.yaml`). Put the values in a Secret and add `secretKeyRef` env
entries; none are configured yet. Callback URLs are
`https://postiz.vps.kubespaces.cloud/integrations/social/<provider>`.

## First start

Open https://postiz.vps.kubespaces.cloud and register the first account
(email/password), or sign in with **Kubespaces**.
