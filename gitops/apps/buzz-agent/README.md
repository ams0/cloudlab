# Buzz agent — `claude`

A Buzz agent running **in the cluster** instead of on a laptop: the `buzz-acp`
harness as PID 1, spawning Claude Code over ACP, connected to the relay under
its own Nostr identity. It appears in Buzz channels as a teammate and stays
online whether or not any desktop is running.

- Image: `ghcr.io/ams0/buzz-agent-claude` (built by `.github/workflows/buzz-agent-image.yml`)
- Relay: `wss://buzz.vps.kubespaces.cloud`
- Agent pubkey: `49c4b7c31c8b97b3be646eda1cf6a5b31c5d2bc820a6924c1a6af9c0e9c81d34`

## Why not kagent

kagent was the original ask, but it cannot host a Buzz agent. kagent runs its
own agents over A2A with its own `Agent`/`ModelConfig` CRDs; a Buzz agent is
the `buzz-acp` harness speaking **ACP over stdio** while holding a Nostr
keypair. Different protocol, different identity model. Buzz already specifies
this deployment itself in [`docs/remote-agents.md`](https://github.com/block/buzz/blob/main/docs/remote-agents.md),
including a Kubernetes binding, so that spec is what this follows.

## How it is launched

The spec's own Kubernetes binding (`buzz-backend-kubernetes`) is driven *from
the desktop*: the app shells out to a local provider binary that creates a bare
Pod with your kubeconfig. That is not used here. The spec explicitly allows
other launchers — "the desktop is **one launcher among many** […] anything that
can set that environment and exec the harness — a bash script, a systemd unit,
a CI job […] — is a conforming launcher" — so this is a plain Flux-managed
Deployment, which keeps the agent in Git with everything else.

What makes a process a live Buzz agent is just: a keypair, an owner reference,
a relay URL, and the harness. No NIP-OA auth tag is minted here — the spec
allows `BUZZ_ACP_AGENT_OWNER` (the owner's pubkey) in its place, which avoids
reproducing an attestation the desktop normally signs.

## Deliberate deviations from the spec

### 1. Deployment, not a bare Pod

The spec forbids controllers: "controller-grade restart machinery
(`Restart=always`-shaped) would resurrect what `!shutdown` and auto-stop
terminate", breaking its *intentional-termination-is-final* invariant.

**Consequence: `!shutdown` from chat will not stop this agent** — the
ReplicaSet recreates it. Stopping is a GitOps action:

```bash
kubectl -n buzz-agent scale deploy/buzz-agent-claude --replicas=0
# or comment the app out of gitops/apps/kustomization.yaml
```

Taken knowingly, because a bare Pod cannot survive what this cluster actually
does — the spec concedes "`restartPolicy` is kubelet-level and cannot survive
*node-level* loss — a drain or API-initiated eviction deletes a bare pod
outright". On a single node that gets rebooted, that is the common failure, and
an always-on teammate is the point. Inactivity auto-stop is therefore disabled
(`BUZZ_ACP_EXIT_AFTER_INACTIVITY=0`) rather than left at its 7200s default, so
the agent does not reap itself into a restart loop.

### 2. A mounted ServiceAccount token, with cluster-admin

The spec makes `automountServiceAccountToken: false` a normative default and
calls the token "an API-stealable credential the agent never needs". It also
names the exception taken here: "API-token access, if ever wanted, is a
**separate explicit opt-in**, not a side effect of naming an SA."

So, plainly: **an agent reachable from a chat channel can change this
cluster.** The controls that make that tolerable are upstream, not in the pod:

- the relay enforces membership (`auth_required: true`) and the owner is its
  only human member
- the harness runs with `respond_to=owner-only` (its default), so only the
  owner's pubkey can drive it -- an invited member could not command an agent
  holding cluster-admin. `BUZZ_ACP_RESPOND_TO_ALLOWLIST` is intentionally unset,
  because the harness ignores it unless `respond_to=allowlist`, and owner-only
  is the stricter of the two

Everything else stays hardened: `runAsNonRoot` with a fixed UID 1000,
`allowPrivilegeEscalation: false`, all capabilities dropped, `RuntimeDefault`
seccomp, no host namespaces.

## The image

`ghcr.io/block/buzz-sprig` carries the `sprig` multicall binary (`buzz-acp`,
`buzz-dev-mcp`, `rg`, `tree`, `git-credential-nostr`, `git-sign-nostr`) on
Alpine with bash and git — but **no Node**, by design: "alternate-harness
dependencies (node for Claude Code / Codex) come via the `image` override
field, not a fatter default."

So `image/Dockerfile` is `FROM` sprig and adds Node plus
`@agentclientprotocol/claude-agent-acp`. The direction matters — the spec
requires that "a conforming custom image is 'buzz-sprig plus your tools', never
'your tools instead'", and that an override still carries the whole runtime
ABI. Both base and result are pinned by digest, because a tag is a mutable
pointer and the object holding it runs with an nsec.

A build-time check fails the image if `claude-agent-acp`, `buzz-acp` or
`buzz-dev-mcp` are missing from `PATH`; the harness resolves
`BUZZ_ACP_AGENT_COMMAND` against `PATH`, so a missing binary would otherwise
show up only as a silently dead agent.

### Cluster tooling

The agent holds cluster-admin, so it also carries the CLIs to use it:

| Tool | Version | Source |
|------|---------|--------|
| `kubectl` | v1.36.4 | `dl.k8s.io` — matches the k0s server exactly |
| `helm` | v3.22.0 | `get.helm.sh` — 3.x, to match helm-controller v1.4.5's Helm 3 release storage |
| `flux` | v2.7.5 | GitHub releases — same pin as `roles/flux/defaults/main.yml`, so CLI and host cannot drift |
| `yq` | v4.54.1 | GitHub releases |
| `jq` | Alpine 3.22 `main` | `apk`, so the signed index covers it |

Every upstream tarball is verified against a per-arch SHA-256 recorded in the
Dockerfile. An unpinned `curl | tar` into a cluster-admin image would reopen
exactly the supply-chain hole the base-image digest pin exists to close.
Alpine's own `kubectl` is not used because it trails a 1.36 server by more than
the ±1 kubectl skew policy allows.

`KUBECONFIG=/etc/buzz-agent/kubeconfig` is baked in, because **`kubectl` does
not fall back to in-cluster config the way client-go does** — without a
kubeconfig it would try `localhost:8080`. That file points at the projected
ServiceAccount and uses `tokenFile:` rather than `token:`, so kubectl re-reads
the token as the kubelet rotates it instead of pinning one that expires. `helm`
and `flux` honour `KUBECONFIG` too, so all three work with no setup.

It sits in `/etc/buzz-agent/` and not `~/.kube/` on purpose: the Deployment
mounts an emptyDir over `/home/agent`, which would mask anything baked into the
home directory.

The default namespace in that context is `default`; the agent is cluster-wide,
so most real work wants `-n <ns>` or `-A`.

The build *executes* each tool (`kubectl version --client`, `helm version`,
`flux --version`, …) rather than just locating it. buildx runs the arm64 stage
under QEMU, so that is a genuine arm64/musl check and would catch a glibc-only
binary before it ever reaches the node.

## Secrets

`buzz-agent-env` (namespace `buzz-agent`, created by `roles/flux`):

| Key | From vault | Notes |
|-----|-----------|-------|
| `BUZZ_PRIVATE_KEY` | `vault_buzz_agent_nsec` | agent identity, read by the harness |
| `NOSTR_PRIVATE_KEY` | `vault_buzz_agent_nsec` | same value; the git helpers read this name |
| `CLAUDE_CODE_OAUTH_TOKEN` | `vault_buzz_claude_oauth_token` | `claude setup-token`; ~1 year, **no auto-refresh** |

## Enabling it

Disabled in `gitops/apps/kustomization.yaml` until both hold, because a pod
that cannot start stalls the `flux-system` Kustomization on its health check:

1. **`ghcr.io/ams0/buzz-agent-claude` must be pullable.** It is currently
   private; `ams0/backstage` is public and the repo uses no `imagePullSecrets`,
   so the matching fix is to flip this package to public in its GitHub package
   settings. GitHub exposes no REST endpoint for that — it is a UI action.
2. **`vault_buzz_claude_oauth_token` must be set**, and `site.yml --tags flux`
   run so the secret exists.

Then uncomment `- buzz-agent` and let Flux reconcile.
