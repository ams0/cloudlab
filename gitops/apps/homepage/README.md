# Homepage

[gethomepage.dev](https://gethomepage.dev) dashboard — the landing page for the
lab at `home.vps.kubespaces.cloud`. Static link tiles for the services that are
currently deployed.

## Resources

- `namespace.yaml` — namespace
- `homepage-helmrepo.yaml` — HelmRepository (jameswynn charts)
- `homepage-helmrelease.yaml` — Flux HelmRelease
- `homepage-httproute.yaml` — Gateway API HTTPRoute for `home.vps.kubespaces.cloud`

No PVC: all configuration is rendered into a ConfigMap from the HelmRelease
values, so there is no writable state to preserve.

## Design decisions

**`HOMEPAGE_ALLOWED_HOSTS` is mandatory.** Homepage v1.x rejects any request
whose `Host` header is not in this list with a 400. Traefik forwards the
original Host, so it must list the public hostname. Adding a new hostname for
this dashboard means adding it here too.

**Chart version vs image tag.** Chart 2.1.0 pins appVersion `v1.2.0`; the image
tag is overridden to track the current release and is Renovate-managed.

**`controller.strategy: Recreate`.** The chart defaults to RollingUpdate with
`maxSurge: 25%`. On this single-node cluster a surging replica has nowhere to
schedule and the rollout stalls, so the old pod is removed first.

**`enableRbac: false`.** The tiles are static links; nothing queries the
Kubernetes API, so the deployment gets no service account permissions.

## Adding a service

Add an entry under `config.services` in the HelmRelease, and if the service
needs a new public hostname, add a matching router to
`ingress/traefik/dynamic.yml`. Icons resolve by name from the
[dashboard-icons](https://github.com/walkxcode/dashboard-icons) set.
