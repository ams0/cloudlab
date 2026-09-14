# OpenCloud

[OpenCloud](https://opencloud.eu) — file sync, share and collaboration.
Authenticates against Keycloak (`kubespaces` realm).

UI: `opencloud.vps.kubespaces.cloud`

## Resources

- `namespace.yaml`
- `opencloud-pvc.yaml` — data (20Gi), config (1Gi), ldap (2Gi), all local-path
- `opencloud-ldap.yaml` — OpenLDAP directory + Service
- `opencloud-deployment.yaml` — OpenCloud single-process server + Service
- `opencloud-httproute.yaml` — Gateway API HTTPRoute
- `ldap-files/` — upstream schema and base LDIF, mounted via configMapGenerator

Keycloak side lives in `gitops/keycloak-resources/`:
`opencloud-client.yaml` (the `web` OIDC client) and `kubespaces-users.yaml`.

## Why there is no Helm chart here

There is no maintained one. `opencloud-eu/helm` was **archived in November 2025**
with this notice:

> Due to the high amount of AI generated contributions and poor maintenance,
> this repository has been archived. For production-ready Helm charts ... please
> use the enterprise offering, available with a business subscription.

Its charts are `v0.2.3` with `appVersion: latest`, written against a much older
OpenCloud (current release is 7.x). The community charts on ArtifactHub are
forks of that same archived work. So these are plain manifests derived from
[opencloud-compose](https://github.com/opencloud-eu/opencloud-compose), which
*is* actively maintained and is upstream's reference deployment.

**When upgrading**, diff against `opencloud-compose/docker-compose.yml` and
`idm/external-idp.yml` rather than trusting these files to still match.

## Why there is an LDAP server

Because Keycloak alone is not enough. Upstream is explicit that *"it is not
supported to run Keycloak with the built-in idm"*. OpenCloud's graph/user
services read the directory over LDAP; the OIDC provider only handles
authentication. So the supported external-IdP shape is:

```
Keycloak (kubespaces realm)   →  authentication  (OIDC)
OpenLDAP                      →  user directory  (autoprovisioned)
OpenCloud                     →  OC_EXCLUDE_RUN_SERVICES=idp,idm
```

A user who logs in for the first time gets an LDAP entry created automatically
(`PROXY_AUTOPROVISION_ACCOUNTS=true`), keyed on the immutable `sub` claim so a
rename in Keycloak does not orphan their files.

### The LDAP image is a known weak point

`bitnamilegacy/openldap` is the frozen public mirror of Bitnami's catalogue,
which moved behind a subscription in 2025 — last build 2025-07. The alternative,
`osixia/openldap`, was last built in 2021. Both are arm64, neither is
maintained. This is the least durable part of the deployment and worth revisiting
if a maintained OpenLDAP image appears.

## Role assignment

`PROXY_ROLE_ASSIGNMENT_DRIVER=default` with `GRAPH_ASSIGN_DEFAULT_USER_ROLE=true`,
so every authenticated Keycloak user gets OpenCloud's default user role.

Upstream's compose instead uses the `oidc` driver reading a `roles` claim, which
requires a Keycloak protocol mapper emitting OpenCloud's role names. Without that
mapper nobody gets any role and the UI is unusable, so this starts permissive.
To tighten: model the roles in the realm, add the mapper, then switch the driver.

To make someone an OpenCloud admin, set `OC_ADMIN_USER_ID` to their Keycloak
`sub` UUID and restart.

## Secrets

None are in Git. `roles/flux` creates them from the vault:

| Secret | Key | Vault key |
|---|---|---|
| `opencloud-ldap` | `adminPassword` | `vault_opencloud_ldap_admin_password` |
| `opencloud-smtp` | `password` | `vault_twenty_smtp_password` (same freedom.nl mailbox) |
| `opencloud-user` (in `keycloak-operator`) | `password` | `vault_opencloud_user_password` |

## Storage

`opencloud-config` holds the service secrets written by `opencloud init` on first
boot. **Losing it invalidates every issued token** and the instance's internal
service auth — it is small but not disposable. `opencloud-data` holds the actual
blobs and search index.
