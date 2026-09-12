# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

CloudLab manages a single Oracle Cloud (OCI) ARM64 host using **Terraform** (infra provisioning), **Ansible** (host configuration), and **Flux CD** (Kubernetes GitOps). The Kubernetes distribution is **k0s** with **Istio** service mesh (ambient mode) and **Gateway API** for routing.

Domain: `*.vps.kubespaces.cloud`

## Commands

### Ansible
```bash
ansible-playbook site.yml                        # Full deployment
ansible-playbook site.yml --tags packages         # Run specific role(s)
ansible-playbook site.yml --tags k0s,flux         # Multiple tags
ansible-playbook site.yml --check --diff          # Dry run
ansible oracle_hosts -m ping                      # Test connectivity
ansible-vault edit group_vars/oracle_hosts/vault.yml   # Edit secrets
```

`ansible.cfg` sets `vault_password_file = .vault_password`, so no `--ask-vault-pass` is needed locally.

Available tags (order matches `site.yml`): `common`, `packages`, `fail2ban`/`security`, `cron`, `docker`, `traefik`/`ingress`, `tailscale`, `sshfs`/`backup`, `borg`/`backup`, `datadog`/`monitoring`, `alloy`/`monitoring`, `k0s`/`kubernetes`, `flux`/`gitops`, `flux-webhook`/`gitops`, `claude-code`/`tools`

### Terraform
```bash
cd terraform && terraform init && terraform apply
./deploy.sh                                       # terraform apply → wait for SSH → ansible-playbook site.yml
```

### Validation

There is no unit test suite. Validate before applying:
```bash
terraform -chdir=terraform fmt -check && terraform -chdir=terraform validate
ansible-playbook site.yml --check --diff
kubectl apply --dry-run=server -f <manifest>      # requires CRDs present
kubectl kustomize gitops/apps/{app}               # verify a kustomization renders
helm lint charts/{chart}
```

### Kubernetes / Flux
```bash
flux reconcile kustomization flux-system --with-source   # Force reconciliation
flux get helmreleases -A                                  # HelmRelease status
flux get all -A                                           # All Flux resources
kubectl get pods -A                                       # Cluster-wide pod status
```

---

## Architecture

### Deployment Flow
```
git push → GitHub Actions (roles/** or ingress/** changes) → Ansible configures host
git push → Flux CD (gitops/** changes) → Reconciles Kubernetes resources every 10m
```

Workflows in `.github/workflows/`:
- `deploy.yml` — runs Ansible on `roles/**` or `ingress/**` changes, **plus a 6-hourly schedule** and manual dispatch (optional `tags`/`limit` inputs). Reaches the host over Tailscale.
- `backstage-image.yml` — builds/pushes `ghcr.io/ams0/backstage` on `gitops/apps/backstage/src/**` changes.
- `helm-chart.yml` — packages and pushes `charts/alarik` to `oci://ghcr.io/ams0` on `charts/alarik/**` changes.

Flux watches `gitops/**` directly from the Git repo; `flux-webhook` (Ansible role + `gitops/flux-receiver/`) gives GitHub a receiver for push-triggered reconciliation instead of waiting for the interval.

`origin` fetches from GitHub (canonical, and the source Flux reads) but pushes to **both** GitHub and the Forgejo mirror at `code.vps.kubespaces.cloud`. If the mirror diverges, realign it with a force-push — never rewrite GitHub.

### Infrastructure Stack
```
OCI ARM64 VM (Terraform)
  └── k0s (Kubernetes, installed via Ansible)
       ├── Istio (ambient mode, service mesh + Gateway API)
       ├── Flux CD (GitOps controller)
       ├── CloudNativePG (PostgreSQL operator)
       ├── Altinity ClickHouse operator
       ├── local-path-provisioner (storage)
       ├── Observability: kube-prometheus-stack + Thanos + Grafana, Loki, Alloy (DaemonSet)
       └── Applications (Helm charts via Flux)
```

Host-level services (Ansible-managed): Traefik (reverse proxy), Tailscale (VPN), Docker, Fail2ban, BorgBackup, Datadog agent, Grafana Alloy (Docker container tailing the journal + `/var/log` files → Loki).

Logging has two Alloy deployments: the **host** one (`roles/alloy/`, ships journald and host log files) and the **cluster** one (`gitops/alloy/`, DaemonSet tailing `/var/log/pods/*`). Both push to the same Loki. Traefik logs via `json-file` + Alloy — never the Loki Docker log driver, which creates a boot-order circular dependency that wedges the host.

---

## Directory Layout

```
terraform/           — OCI VM provisioning (VCN, subnet, security list, compute)
roles/               — 15 Ansible roles orchestrated by site.yml
  common/            — Base system configuration
  packages/          — System packages
  fail2ban/          — Intrusion prevention
  cron/              — Scheduled tasks
  docker/            — Container runtime
  traefik/           — Reverse proxy (host-level, Docker-based)
  tailscale/         — Mesh VPN client
  sshfs/             — Remote filesystem mounts
  borg/              — BorgBackup for host-level backups
  datadog/           — Monitoring agent
  alloy/             — Grafana Alloy log shipper (Docker, host logs → Loki)
  k0s/               — Kubernetes distribution
  flux/              — Flux CD bootstrap
  flux-webhook/      — GitHub webhook receiver for Flux
  claude-code/       — Claude Code tooling
ingress/             — Traefik reverse proxy configs (Docker-based, on host)
group_vars/
  oracle_hosts/
    main.yml         — Ansible variables
    vault.yml        — Encrypted secrets (ansible-vault)
gitops/              — All Kubernetes manifests, Flux-managed
  kustomization.yaml — Root kustomization (entry point for Flux)
  apps/              — Application deployments (each app is a subdirectory)
  observability/     — Prometheus (kube-prometheus-stack), Grafana, Thanos
  loki/              — Loki (SimpleScalable mode) + shared `grafana` HelmRepository
  alloy/             — Alloy DaemonSet (cluster log collection)
  clickhouse/        — Altinity ClickHouse operator
  istio/             — Istio service mesh (ambient mode: base, cni, istiod, ztunnel)
  cnpg/              — CloudNativePG operator (cluster-wide)
  databases/         — Shared database definitions
  gateways/          — Istio Gateway + config
  gateway-api/       — Gateway API CRDs
  local-path-provisioner/ — Storage provisioner for single-node
  argocd/            — ArgoCD (alternative GitOps)
  velero/            — Backup and disaster recovery
  flux-receiver/     — Webhook receiver config
  system/            — Empty placeholder kustomization (resources: [])
charts/              — Local Helm charts (alarik, forgejo-runner); alarik is published to GHCR by CI
.github/workflows/   — Ansible deploy, Backstage image build, Helm chart push
```

Anything under `gitops/` only reaches the cluster if it is reachable from `gitops/kustomization.yaml` (which pulls in `gitops/apps/kustomization.yaml` for apps).

---

## Conventions

### Adding a New Application

Each app in `gitops/apps/{app-name}/` **must** follow this structure:

```
gitops/apps/{app-name}/
├── kustomization.yaml            # Lists all resources for this app
├── namespace.yaml                # Namespace definition (singular, not namespaces.yaml)
├��─ {app}-helmrepo.yaml           # HelmRepository source
│   OR {app}-ocirepository.yaml   # OCI chart source (for OCI-hosted charts)
├── {app}-db-helmrelease.yaml     # CNPG PostgreSQL cluster (if app needs a database)
├── {app}-helmrelease.yaml        # Flux HelmRelease (the app itself)
├── {app}-pvc.yaml                # PersistentVolumeClaim (if app needs persistent storage)
├── {app}-httproute.yaml          # Gateway API HTTPRoute for external access
└── README.md                     # Documents the app, its values, and design decisions
```

After creating the app directory, add it to `gitops/apps/kustomization.yaml`. Comment it out with `# scaled to zero` if not deploying immediately.

### Namespace Convention

- File is always `namespace.yaml` (singular)
- Each app gets its own namespace matching the app name
- Exception: Rancher uses `cattle-system` (Rancher convention)

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: {app-name}
  labels:
    name: {app-name}
```

### HelmRelease Convention

All HelmReleases live in `flux-system` namespace with `targetNamespace` pointing to the app namespace:

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: {app}
  namespace: flux-system
  labels:
    app: {app}
spec:
  interval: 10m
  timeout: 5m          # 10m for complex apps (minecraft, openclaw, alarik)
  targetNamespace: {app}
  chart:
    spec:
      chart: {chart-name}
      sourceRef:
        kind: HelmRepository    # or OCIRepository via chartRef
        name: {app}
        namespace: flux-system
      interval: 5m0s
  install:
    createNamespace: true
    remediation:
      retries: 3
  upgrade:
    remediation:
      retries: 3
  values:
    ingress:
      enabled: false            # Always disable — use HTTPRoute instead
    # ... app-specific values
```

Service naming: Helm produces `<release-name>-<chart-name>`, e.g. release `backstage` + chart `backstage` = service `backstage-backstage`.

### Chart Sources

Three types of chart source are used:

1. **HelmRepository** (most common) — `{app}-helmrepo.yaml`:
   ```yaml
   apiVersion: source.toolkit.fluxcd.io/v1
   kind: HelmRepository
   metadata:
     name: {app}
     namespace: flux-system
   spec:
     interval: 1h
     url: https://...
   ```

2. **OCIRepository** — `{app}-ocirepository.yaml` for OCI-hosted charts (n8n, forgejo, keycloak, vikunja, omni, alarik). Referenced via `chartRef` instead of `chart.spec.sourceRef`.

3. **GitRepository** — rare, only Garage uses this for building from a Git repo path.

### HTTPRoute Convention

All routes reference the shared Istio gateway. The standard service port varies by app (check the chart docs):

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: {app}
  namespace: {app}
spec:
  parentRefs:
    - name: gateway
      namespace: istio-system
      sectionName: http
  hostnames:
    - "{app}.vps.kubespaces.cloud"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: {release}-{chart}    # e.g. backstage-backstage
          port: {service-port}        # varies: 80, 7007, 5678, 8080, 3000, etc.
```

Some apps use custom subdomains: `code.` (forgejo), `auth.` (keycloak), `dash.` (dashy), `todo.` (vikunja), `chat.` (openwebui), `claw.` (openclaw), `wiki.` (xwiki), `uptime.` (uptime-kuma), `registry.` (harbor), `s3.` (garage).

### Database Convention (CNPG PostgreSQL)

Apps needing a relational database use CloudNativePG via a separate HelmRelease. The CNPG operator and its HelmRepository are defined cluster-wide in `gitops/cnpg/`.

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: {app}-database
  namespace: flux-system
  labels:
    app: {app}
spec:
  # ... standard flux settings ...
  chart:
    spec:
      chart: cluster
      version: ">=0.0.10"
      sourceRef:
        kind: HelmRepository
        name: cnpg                    # Cluster-wide, in flux-system
        namespace: flux-system
      interval: 1m
  dependsOn:
    - name: cnpg
      namespace: flux-system
  values:
    type: postgresql
    mode: standalone
    version:
      postgresql: "18"
    cluster:
      instances: 1
      initdb:
        database: {app}
        encoding: UTF8
        localeCType: C
        localeCollate: C
        owner: {app}
    backups:
      enabled: false
```

CNPG auto-generates a secret named `{release}-{chart}-cluster-app` containing `host`, `port`, `dbname`, `user`, `password`, and `uri`. Apps reference these via `secretKeyRef`. The read-write service is `{release}-{chart}-cluster-rw`.

Apps with CNPG databases: n8n, forgejo, keycloak, authentik, coder, vikunja, outline, xwiki, backstage.

Exceptions:
- **Wekan** uses MongoDB (bundled subchart, Meteor.js legacy)
- **Harbor** uses its own bundled PostgreSQL (custom image `ams0/harbor-db`)
- **Supabase** bundles its own PostgreSQL
- **Actual, Uptime Kuma, Omni** use embedded SQLite (no external DB)

### PVC Convention

PVCs are defined as **separate resources** (not inline in HelmRelease) so they survive Helm upgrades and uninstalls. All use `local-path` storageClass (single-node cluster, data on host filesystem).

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: {app}-pvc
  namespace: {app}
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  resources:
    requests:
      storage: {size}             # 5Gi typical, 30Gi for forgejo, 20Gi for minecraft
```

Referenced in HelmRelease via `existingClaim: {app}-pvc` (exact value key varies by chart).

Exception: **Waha** uses raw Deployment manifests (no HelmRelease) with direct PVC volume mounts.

### Renovate Image Tag Pattern

Image tags use inline comments for Renovate auto-updates:
```yaml
tag: "2.15.0" # renovate: datasource=docker depName=n8nio/n8n
```

### Scaling Apps Down

To temporarily disable an app without removing its directory, comment it out in `gitops/apps/kustomization.yaml`:
```yaml
#  - minecraft  # scaled to zero — resource savings
```

### Secrets

- **Ansible secrets**: encrypted with `ansible-vault` in `group_vars/oracle_hosts/vault.yml`
- **Kubernetes database secrets**: auto-generated by CNPG operator (referenced via `secretKeyRef`)
- **App secrets**: manually created Kubernetes secrets (referenced in HelmRelease values). Never committed to Git.
- **Flux valuesFrom**: used by Tailscale to inject OAuth credentials from a Secret at reconciliation time (keeps secrets out of HelmRelease values)

### SMTP Convention

Apps needing email use Google Workspace SMTP relay:
- Host: `smtp-relay.gmail.com` (most apps) or `smtp.gmail.com` (vikunja)
- Port: 587 with STARTTLS
- Credentials from per-app Kubernetes secrets (e.g. `forgejo-smtp`, `keycloak-smtp`)

### Single-Node Constraints

The cluster is one ARM64 node, so a rolling update that surges a second replica has nowhere to schedule and stalls indefinitely (seen with coder and istiod). When upgrading a chart:
- Pin chart versions explicitly rather than tracking a floating range
- Set `maxSurge: 0` (or the chart's equivalent) so the old pod is removed before the new one starts
- All storage is `local-path` on the host filesystem — a PVC is bound to this node, and deleting it deletes the data

---

## Ansible Conventions

### Role Structure
Each role in `roles/{role-name}/` follows standard Ansible layout: `tasks/main.yml`, `handlers/main.yml`, `templates/`, `files/`, `defaults/main.yml`.

### Variables
- Public variables: `group_vars/oracle_hosts/main.yml`
- Encrypted secrets: `group_vars/oracle_hosts/vault.yml` (edit with `ansible-vault edit`)
- Role-specific defaults: `roles/{role}/defaults/main.yml`

### CI/CD
GitHub Actions triggers on `roles/**` or `ingress/**` changes. Supports manual dispatch with optional `--tags` and `--limit` parameters.

---

## Terraform Conventions

- Single environment in `terraform/`
- OCI provider for ARM64 VM provisioning
- State stored locally (`terraform.tfstate`) — not remote
- Variables in `terraform.tfvars` (not committed), example in `terraform.tfvars.example`

---

## Current Applications

`gitops/apps/kustomization.yaml` is the source of truth — check it rather than trusting this list.

### Active (uncommented in the apps kustomization)
Keycloak, n8n, Stakater Reloader, Garage, Forgejo, Dashy, Actual, OpenClaw, Authentik, Open WebUI, Coder, Vikunja, WAHA, Omni, Tailscale, Alarik, Uptime Kuma, Outline, RustFS, Backstage, Atlantis

### Commented out
Harbor, Minecraft, Rancher, XWiki, Wekan (resource savings); Supabase (StatefulSet immutable-field error blocking Flux); Vault (awaiting initialization)

### In repo, not referenced by any kustomization
Draw (Excalidraw), CodiMD, Matrix (OCIRepository only), Nexus (stub — namespace only, no HelmRelease)

### Observability
Prometheus (kube-prometheus-stack) + Thanos + Grafana + Alertmanager in `gitops/observability/`; Loki in `gitops/loki/`; Alloy in `gitops/alloy/`
