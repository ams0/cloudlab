# Keycloak Operator (EDP)

[epam/edp-keycloak-operator](https://github.com/epam/edp-keycloak-operator) —
manages Keycloak **realms, groups, roles, users, clients, client scopes, auth
flows and identity providers** as Kubernetes CRs, so they can be GitOps-managed
like everything else here.

It has no UI and serves no traffic, so there is no HTTPRoute.

## Resources

- `namespace.yaml` — namespace
- `keycloak-operator-helmrepo.yaml` — HelmRepository (EDP stable charts)
- `keycloak-operator-helmrelease.yaml` — Flux HelmRelease, `dependsOn: keycloak`
- `keycloak-resources-kustomization.yaml` — a second Flux Kustomization for the CRs

The Keycloak CRs themselves live in **`gitops/keycloak-resources/`**, not here.

## Why this operator and not the official one

The official Keycloak operator (`k8s.keycloak.org`) does **not** manage users or
groups. Checking the CRDs it actually ships:

| Release | CRDs |
|---------|------|
| 26.0.0, 26.4.0 | `Keycloak`, `KeycloakRealmImport` |
| 26.7.3 (ours) | + `KeycloakOIDCClient`, `KeycloakSAMLClient` |

`KeycloakRealmImport` takes a whole `RealmRepresentation` and runs a Job — import
semantics, not continuous reconciliation — and it requires `keycloakCRName`,
meaning the operator must own the Keycloak server through its own `Keycloak` CR.
Our Keycloak comes from the codecentric `keycloakx` chart, so adopting it would
mean replacing the deployment.

(Plenty of older blog posts show `KeycloakUser` / `KeycloakRealm` CRDs. Those
belong to the pre-Quarkus operator, ≤ KC 19, and were dropped in the v20
rewrite.)

The EDP operator instead connects to an **existing** Keycloak over its admin
API, so our deployment is untouched.

## Authentication

The operator authenticates as the `keycloak-operator` **service-account client**
in the `master` realm using the `client_credentials` grant — the Keycloak admin
user's password never enters the cluster.

Bootstrapping is necessarily imperative (the operator needs a credential before
it can manage anything). The client was created through the admin API and its
secret stored as `vault_keycloak_operator_client_secret`; `roles/flux` creates
the `keycloak-operator-auth` Secret from it, the same way every other app secret
here is created.

To rotate: regenerate the client secret in Keycloak, update the vault value, delete
the Secret, and re-run `ansible-playbook site.yml --tags flux`.

## Configuration notes

**`enableWebhooks: false`.** The chart defaults this on, which creates a
`ValidatingWebhookConfiguration` and a cert-manager `Certificate`. There is no
cert-manager in this cluster — TLS is terminated by host Traefik — so the
webhook would wait forever on a certificate that is never issued.

**`clusterReconciliationEnabled: false`.** The operator only watches this
namespace, so realm CRs must live here too. Cluster-scoped `ClusterKeycloak` and
`ClusterKeycloakRealm` resources are ignored. Turn it on if realm resources ever
need to sit beside the apps that consume them.

**Public URL in the connection CR.** Keycloak runs with
`KC_HOSTNAME=https://auth.vps.kubespaces.cloud`, so tokens carry that issuer.
Addressing it by the same name avoids issuer mismatches; the cost is a hairpin
through host Traefik, which is irrelevant at this request volume.

## Why the CRs are in a separate Kustomization

They cannot sit in the root `gitops` kustomization alongside the HelmRelease.
kustomize-controller server-side dry-runs every object before applying anything,
and a CR whose CRD does not exist yet fails that dry-run:

```
Keycloak/keycloak-operator/keycloak dry-run failed:
  no matches for kind "Keycloak" in version "v1.edp.epam.com/v1"
```

That failure aborts the **entire** apply — so the HelmRelease that would have
installed the CRD is never created, and it deadlocks instead of self-healing. It
also holds the whole `flux-system` Kustomization at `Ready=False`, which stalls
every other app.

So `gitops/keycloak-resources/` is applied by its own Flux Kustomization that
`dependsOn: flux-system`. It reconciles after the operator is installed and
retries on its own interval until the CRDs exist. Any new realm/group/role CRs
belong in that directory, not in `gitops/apps/`.

## Usage

Add new CRs to `gitops/keycloak-resources/` (and list them in that directory's
`kustomization.yaml`). They go in the `keycloak-operator` namespace and
reference the connection by `keycloakRef`:

```yaml
apiVersion: v1.edp.epam.com/v1
kind: KeycloakRealm
metadata:
  name: apps
  namespace: keycloak-operator
spec:
  realmName: apps
  keycloakRef:
    name: keycloak
    kind: Keycloak
---
apiVersion: v1.edp.epam.com/v1
kind: KeycloakRealmGroup
metadata:
  name: platform-admins
  namespace: keycloak-operator
spec:
  name: platform-admins
  realm: apps
```

Available kinds: `KeycloakRealm`, `KeycloakRealmUser`, `KeycloakRealmGroup`,
`KeycloakRealmRole`, `KeycloakRealmRoleBatch`, `KeycloakClient`,
`KeycloakClientScope`, `KeycloakAuthFlow`, `KeycloakRealmIdentityProvider`,
`KeycloakRealmComponent`, `KeycloakOrganization`.

## A caution on managing users in Git

Users are *state*, not configuration — a Git-declared user list drifts the moment
someone self-registers, and passwords do not belong in a repo.
`KeycloakRealmUser` can take its password from a Secret, which is fine for seeded
service accounts, but real humans should arrive through federation or be created
out of band.

Leave the `master` realm's admin user out of this entirely — it is the
break-glass path if the operator or its credential breaks.
