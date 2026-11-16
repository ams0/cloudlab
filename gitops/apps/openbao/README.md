# OpenBao

[OpenBao](https://openbao.org) — the open-source (MPL) fork of Vault. Deployed
here as the **SSH certificate authority for Warpgate**: Warpgate asks OpenBao to
sign a 5-minute user certificate per session, and target hosts trust the CA via
`TrustedUserCAKeys` instead of holding Warpgate's key.
See <https://warpgate.null.page/targets/ssh/#ssh-certificates-signed-by-vault-openbao>.

UI/API: `https://vault.vps.kubespaces.cloud`
In-cluster: `http://openbao.openbao.svc:8200`

Replaces the never-initialized HashiCorp Vault app in `gitops/apps/vault/`.

## Resources

- `namespace.yaml`
- `openbao-helmrepo.yaml` — `https://openbao.github.io/openbao-helm`
- `openbao-pvc.yaml` — 2Gi local-path, named `data-openbao-0` so the
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
| Plaintext listener | TLS ends at Traefik; in-cluster hops are covered by ambient ztunnel mTLS. |

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
kubectl -n openbao exec -ti openbao-0 -- bao operator init -recovery-shares=1 -recovery-threshold=1
kubectl -n openbao exec -ti openbao-0 -- bao status   # Sealed: false
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
  "allowed_users": "root,ubuntu",
  "default_extensions": {"permit-pty": ""},
  "ttl": "5m",
  "max_ttl": "10m"
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

# 4. CA public key → each target host
bao read -field=public_key ssh/config/ca   # → /etc/ssh/warpgate_ca.pub
#   sshd_config: TrustedUserCAKeys /etc/ssh/warpgate_ca.pub
```

Then in Warpgate (**requires v0.30+**; currently pinned at v0.29.0):
`Config → Secret backends` → address `http://openbao.openbao.svc:8200`,
Kubernetes auth, role `warpgate`, allowed prefix `ssh/sign/warpgate`. On the SSH
target choose "Certificate signed by a secret backend's SSH CA", mount `ssh`,
role `warpgate`.
