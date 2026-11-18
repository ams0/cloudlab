# OpenTodo

[OpenTodoApp/OpenTodo](https://github.com/OpenTodoApp/OpenTodo) (AGPL-3.0) — a
local-first task manager, at https://todo.vps.kubespaces.cloud.

## Resources

- `opentodo-ocirepository.yaml` — upstream chart `oci://ghcr.io/opentodoapp/charts/opentodo`,
  pinned to `1.5.0` (chart version = app version)
- `opentodo-helmrelease.yaml` — release `opentodo-opentodo` (Service on 8080)
- `opentodo-pvc.yaml` — 2Gi local-path on `/data` (SQLite, attachments, local backups)
- `opentodo-httproute.yaml` — `todo.vps.kubespaces.cloud`; Traefik router `todo`
  already existed (left over from Vikunja)
- Keycloak client: `gitops/keycloak-resources/opentodo-client.yaml`

## Design decisions

| Decision | Why |
|---|---|
| Upstream chart via OCIRepository | Upstream publishes one; it already runs one replica, `Recreate`, non-root, read-only rootfs. |
| Setup token from `opentodo-secrets` (`setupToken.existingSecret`) | A chart-generated token would change on every Flux reconcile. Created by `roles/flux` from `vault_opentodo_setup_token`. |
| `OPENTODO_BASE_URL=https://todo.vps.kubespaces.cloud` | Cookies, the origin check and the OIDC redirect URI are bound to it. Requests for any other host are refused as cross-site. |
| `OPENTODO_TRUSTED_PROXIES` unset | The default trusts private ranges, which covers Traefik → Istio → pod. |
| Keycloak via `OPENTODO_OIDC_*` env | Locks issuer/client in Settings. "Allow new accounts via SSO" and "SSO only" are toggled in **Settings → People → Single sign-on**. |

## First start

1. Open https://todo.vps.kubespaces.cloud and create the owner account. The
   setup screen asks for the setup token:
   `kubectl -n opentodo get secret opentodo-secrets -o jsonpath='{.data.setup-token}' | base64 -d`
2. Link Keycloak to the owner by hand: **Settings → Account → Security → Linked
   accounts** (the owner is never linked by email alone).
3. Optionally enable **Allow new accounts via SSO** so other realm users can sign in.

## Upgrades and backups

Bump `ref.tag` in the OCIRepository. Migrations run on start and there are no
down-migrations, so back up first. The image has no shell (`kubectl exec`/`cp` do
not work); use **Settings → Server → Backups** or copy the local-path directory
on the host.
