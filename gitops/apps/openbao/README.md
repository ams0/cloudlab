# OpenBao

[OpenBao](https://openbao.org) — the open-source (MPL) fork of Vault. Deployed
here as the **SSH certificate authority for Warpgate**: Warpgate asks OpenBao to
sign a 5-minute user certificate per session, and target hosts trust the CA via
`TrustedUserCAKeys` instead of holding Warpgate's key.
See <https://warpgate.null.page/targets/ssh/#ssh-certificates-signed-by-vault-openbao>.

UI/API: `https://vault.vps.kubespaces.cloud`
In-cluster: `http://openbao-openbao.openbao.svc:8200`

Replaces the never-initialized HashiCorp Vault app in `gitops/apps/vault/`.

## Resources

- `namespace.yaml`
- `openbao-helmrepo.yaml` — `https://openbao.github.io/openbao-helm`
- `openbao-pvc.yaml` — 2Gi local-path, named `data-openbao-openbao-0` so the
  StatefulSet's volumeClaimTemplate adopts it (Flux-owned → survives uninstall)
- `openbao-helmrelease.yaml` — chart `0.30.7` (OpenBao v2.7.2), standalone,
  pebbledb storage; the chart emits the HTTPRoute itself

Injector and CSI provider are disabled — nothing consumes secrets from OpenBao yet.

## Design decisions

| Decision | Why |
|---|---|
| **Static seal** (auto-unseal from `openbao-unseal` Secret) | Otherwise every restart leaves OpenBao sealed and Warpgate SSH logins fail until a human unseals. Trade-off: read on that Secret = can decrypt storage. Acceptable on a single-admin, single-node cluster. |
| Readiness probe uses `/v1/sys/health?uninitcode=204` | The default `bao status` probe fails before init, so Helm's install wait would time out on first deploy. Sealed still = not Ready. |
| `updateStrategyType: RollingUpdate` | Chart default `OnDelete` silently ignores config changes until the pod is deleted. One replica → no surge. |
| Plaintext listener | TLS ends at Traefik; the Warpgate → OpenBao hop is plaintext pod-to-pod on the single node (neither namespace is in the ambient mesh — enrolling both would add ztunnel mTLS). |

## Secrets

| Secret | Key | Ansible Vault var | Created by |
|---|---|---|---|
| `openbao-unseal` | `key` (64 hex chars) | `vault_openbao_unseal_key` | `roles/flux` |

Losing `vault_openbao_unseal_key` makes the PVC unreadable. **Rotation:** move
the current key into `previous_key`/`previous_key_id` in the seal stanza, put
the new one in `current_key` with a new `current_key_id`, then update the vault
var and Secret.

## First-time init (once)

With a static seal, `init` returns **recovery keys** (not unseal keys) plus the
root token. Store both outside the cluster.

```bash
kubectl -n openbao exec -ti openbao-openbao-0 -- bao operator init -recovery-shares=1 -recovery-threshold=1
kubectl -n openbao exec -ti openbao-openbao-0 -- bao status   # Sealed: false
```

## Warpgate SSH CA setup

Run with `BAO_ADDR=https://vault.vps.kubespaces.cloud` and the root token.

```bash
# 1. SSH CA
bao secrets enable ssh
bao write ssh/config/ca generate_signing_key=true key_type=ed25519

# 2. Role Warpgate signs with (allow_user_key_ids is mandatory —
#    Warpgate always sets key ID warpgate:<user>:<session>)
bao write ssh/roles/warpgate - <<'JSON'
{
  "key_type": "ca",
  "allow_user_certificates": true,
  "allow_user_key_ids": true,
  "allowed_users": "root,deploy,ubuntu",
  "default_extensions": {"permit-pty": ""}
}
JSON

# 3. Policy + Kubernetes auth bound to Warpgate's pod service account,
#    so no OpenBao credential is stored in Warpgate
bao policy write warpgate-ssh - <<'HCL'
path "ssh/sign/warpgate" { capabilities = ["update"] }
HCL
bao auth enable kubernetes
bao write auth/kubernetes/config kubernetes_host=https://kubernetes.default.svc
bao write auth/kubernetes/role/warpgate \
  bound_service_account_names=warpgate-warpgate \
  bound_service_account_namespaces=warpgate \
  token_policies=warpgate-ssh token_ttl=1h

# 4. CA public key → each target host. For the OCI host this is Ansible:
#    roles/common installs warpgate_ssh_ca_public_key (group_vars) and an
#    sshd drop-in with TrustedUserCAKeys.
bao read -field=public_key ssh/config/ca
```

Writing `ssh/roles/warpgate` replaces the whole role — always resend every
field, not just the one you are changing.

## Current state (2026-11-16)

All of the above is applied. Warpgate side (lives in Warpgate's database, not Git):

| Object | Value |
|---|---|
| Secret backend | `openbao` → `http://openbao-openbao.openbao.svc:8200`, Kubernetes auth, role `warpgate`, allowed path `ssh/sign/warpgate` |
| Target | `cloudlab-host` → `ubuntu@10.20.10.147:22`, auth *Certificate* (backend `openbao`, mount `ssh`, role `warpgate`) |
| Known host | the host's ed25519 key, verified against `/etc/ssh/ssh_host_ed25519_key.pub` |
| Role | `infra` → `cloudlab-host`, granted to `admin` |

Connect: `ssh -p 2222 admin:cloudlab-host@warpgate.vps.kubespaces.cloud`

sshd on the target logs each login as
`ED25519-CERT … ID warpgate:<user>:<session>`, and Warpgate audits each
signing as `SshCertificateIssued`.

New targets need: the principal (login user) in the role's `allowed_users`,
the CA in `TrustedUserCAKeys`, and the host key trusted in Warpgate (an
interactive first login prompts for it; `exec`-only sessions cannot).
