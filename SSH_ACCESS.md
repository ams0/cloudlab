# SSH access: Warpgate + OpenBao + Keycloak

How people get a shell on the cloudlab host, why it is built this way, and how
to operate it. Set up 2026-11-16/17.

Component details live next to each app:
[`gitops/apps/warpgate/README.md`](gitops/apps/warpgate/README.md) and
[`gitops/apps/openbao/README.md`](gitops/apps/openbao/README.md) (the latter
has the exact OpenBao commands).

## TL;DR

```bash
ssh -p 2222 alessandro:cloudlab@warpgate.vps.kubespaces.cloud
#  1. your SSH key is checked by Warpgate
#  2. Warpgate prints a link → open it, sign in with Kubespaces (Keycloak), Approve
#  3. you land on the host as unix user `alessandro` (passwordless sudo)
```

Break-glass, no Keycloak: `ssh -p 2222 admin:cloudlab-host@warpgate.vps.kubespaces.cloud`
(local Warpgate `admin`, lands as `ubuntu`).

## Architecture

There are **two independent hops**, each with its own authentication:

```
 you ──(1)──▶ Warpgate (:2222) ──(2)──▶ host sshd (:22, private IP)
      SSH key + Keycloak             short-lived certificate
      web approval                   signed by OpenBao
```

1. **You → Warpgate** answers *who are you?* Your public key (stored in
   Warpgate) **and** a browser approval in the Warpgate UI, which you can only
   reach through Keycloak SSO. Nothing from this hop is forwarded to the host.
2. **Warpgate → host** answers *may this session log in as account X?* Per
   session, Warpgate generates a throwaway key pair, asks OpenBao (SSH secrets
   engine, mount `ssh/`, role `warpgate`) to sign it for principal X, and
   connects with that certificate. The host trusts only the OpenBao CA
   (`TrustedUserCAKeys /etc/ssh/warpgate_ca.pub`).

Network path for hop 1: client `:2222` → OCI security list → host Traefik TCP
entrypoint `ssh` → PROXY v2 → NodePort `30222` → Warpgate pod. Warpgate sees the
real client IP.

Warpgate authenticates to OpenBao with its **Kubernetes service account**
(`auth/kubernetes`, role `warpgate`, policy `warpgate-ssh` = `update` on
`ssh/sign/warpgate` only). No OpenBao credential is stored in Warpgate.

### Proof it is the OpenBao CA

The host's sshd logs every Warpgate session as:

```
Accepted publickey for alessandro ... ED25519-CERT SHA256:… ID warpgate:alessandro:<session> … CA ED25519 SHA256:+Abn4WRT0ggoghoVj2Lem4NcSAc6RdKMd0zDga+BlDI
```

That CA fingerprint is OpenBao's: `curl -s https://vault.vps.kubespaces.cloud/v1/ssh/public_key | ssh-keygen -lf -`.

## Design decisions (why)

| Decision | Why |
|---|---|
| **Certificates from OpenBao, not a static Warpgate key** on the host | No long-lived key that opens the host. Each cert lives minutes, names one principal, and carries the Warpgate user + session in its key ID, so sshd logs are attributable. Revoking = stop signing. |
| **Kubernetes auth** Warpgate → OpenBao | No secret to store or rotate. Only the `warpgate-warpgate` service account in `warpgate` can sign, and only on `ssh/sign/warpgate`. |
| **Explicit `allowed_users`** on the OpenBao role (not `*`) | OpenBao refuses to sign for an account nobody intended to expose (e.g. `root` is listed only for the break-glass flow). |
| **Target `cloudlab` with an empty username** | Warpgate then uses the *Warpgate* username as the login account and cert principal. One target serves every person, and each lands in their own account: own home, own sudo log, own `who` entry. |
| **One unix account per person, created by Ansible** | sshd needs the account to exist before it accepts any certificate. The account has no password and no `authorized_keys`, so the OpenBao cert is the only way in. |
| **Auth policy `PublicKey + WebUserApproval`** on SSH | Without it, an SSH key alone gets you in and Keycloak is never consulted, so disabling someone in Keycloak would not cut their SSH access. With it, every session needs a browser approval, and the browser login *is* Keycloak (users have no Warpgate password). Key = something you have; Keycloak = the central on/off switch. |
| **OpenBao login via Keycloak (OIDC)**, root token revoked | Humans log in to OpenBao the same way as everywhere else. Recovery keys + `bao operator generate-root` stay as break-glass. |
| **Keep local break-glass** (Warpgate `admin`, target `cloudlab-host` → `ubuntu`) | If Keycloak or the realm is broken, you can still get in. Its password is in Secret `warpgate/warpgate-secret` (`adminPassword`). |

### Rejected: canonical/authd

[authd](https://github.com/canonical/authd) (Keycloak via the `authd-oidc`
broker, device-code flow, creates the account on first login) was evaluated and
**not adopted**:

- Certificate/public-key logins **bypass authd entirely** (authd's own security
  doc says so), so it does nothing on the Warpgate path.
- Accounts appear only after an authd (device-code) login **directly on :22**.
  That means a second login path that skips Warpgate's recording and single
  entry point.
- Account names are the IdP handle (`alessandro@kubespaces.io`), which would
  force Warpgate usernames and OpenBao `allowed_users` to be emails.

authd makes sense as a *replacement* for Warpgate on hosts where you want direct
Keycloak login. It is not an add-on to this design.

## How to

### Add a person

All four steps are needed. Each one blocks at a different point if missed.

1. **Keycloak**: a `KeycloakRealmUser` in
   `gitops/keycloak-resources/kubespaces-users.yaml` with `email`,
   `emailVerified: true` and `roles: [default-roles-kubespaces]`. *Missing →
   Keycloak login or the account console fail.*
2. **Warpgate** (admin UI → Users): create user `<name>`, add an **SSO**
   credential (provider `keycloak`, their Keycloak email), grant role `infra`,
   optionally add their SSH public key, and set **Auth policy → SSH** to
   *Public key + Web approval*. *Missing → "No user matching <email>".*
3. **Host account**: add `- name: <name>` (and `sudo: true` if wanted) to
   `warpgate_users` in `group_vars/oracle_hosts/main.yml`, then
   `ansible-playbook site.yml --tags common`. *Missing → sshd rejects the cert.*
4. **OpenBao**: append `<name>` to `allowed_users` in `ssh/roles/warpgate`.
   Writing a role **replaces it entirely**, so read it, change the one field, and
   POST every field back. *Missing → OpenBao refuses to sign.*

To give someone OpenBao UI access as well, add their email to `bound_claims.email`
on `auth/oidc/role/default` (it grants the `admin` policy).

### Remove a person

Disable them in Keycloak first: this immediately stops new SSH sessions, because
the web approval cannot be completed. Then undo steps 2–4 above.

### Change someone's email

The email is matched in three places. Change all of them together:

1. `email:` in their `KeycloakRealmUser` (in Git, **not** the Keycloak UI: the
   operator reconciles the CR and would revert a UI edit);
2. their Warpgate SSO credential (**Change** next to it);
3. OpenBao `auth/oidc/role/default` `bound_claims.email`. Temporarily list old
   and new, then drop the old one after a successful login.

The username, unix account and certificates are keyed on the username, not the
email, so SSH itself is unaffected.

### Scripts and automation

The `WebUserApproval` step blocks non-interactive `ssh`/`scp`/`rsync`. For
automation, use a dedicated Warpgate user whose SSH policy is *Public key* only,
or a one-off Warpgate **ticket** (`ssh -p 2222 ticket-<secret>@warpgate.vps.kubespaces.cloud`).

## Gotchas found while building this

- **Keycloak account console "Server responded with an invalid status"**: the
  user had no realm roles. The EDP operator syncs `roles:` to exactly what the
  CR lists, so it must include `default-roles-kubespaces`. Log out and in after
  fixing, because the old token lacks the role.
- **Warpgate exec-only sessions cannot accept an unknown host key.** Register a
  new target's host key via the admin UI/API (SSH keys → known hosts) after
  checking it against `/etc/ssh/ssh_host_ed25519_key.pub` on the target.
- **Flux release naming**: OpenBao resources are `openbao-openbao`
  (`targetNamespace` makes the release `<ns>-<name>`).

## What lives outside Git

Re-create by hand after a wipe; commands are in the app READMEs.

| System | State |
|---|---|
| OpenBao | `ssh/` engine + CA key, role `warpgate`, policies `warpgate-ssh` and `admin`, `auth/kubernetes` role `warpgate`, `auth/oidc` config + role `default` |
| Warpgate DB | secret backend `openbao`, targets `cloudlab-host` and `cloudlab`, known host key, role `infra`, users `admin` and `alessandro` (SSO credential, public key, auth policy, admin role `warpgate:admin`) |

In Git: OpenBao/Warpgate deployments, Keycloak clients and users, the host CA
trust and unix accounts (`roles/common`), the Traefik `:2222` entrypoint, and the
OCI firewall rule (`terraform/main.tf`).
