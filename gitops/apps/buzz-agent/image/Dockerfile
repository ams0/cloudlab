# Buzz agent runtime: buzz-sprig + Claude Code + cluster tooling.
#
# buzz-sprig is Alpine + bash + git + CA certs + the static musl `sprig`
# multicall binary (buzz-acp, buzz-dev-mcp, rg, tree, git-credential-nostr,
# git-sign-nostr). It deliberately ships WITHOUT Node: per the remote-agents
# spec, "alternate-harness dependencies (node for Claude Code / Codex) come via
# the `image` override field, not a fatter default."
#
# The spec also constrains what an override may be: "An image override MUST
# contain the runtime ABI -- the `buzz-acp` entrypoint and everything
# §Entrypoint and launch ABI requires [...] A conforming custom image is
# 'buzz-sprig plus your tools', never 'your tools instead'." Hence FROM sprig
# and add to it, rather than installing sprig into a Node image.
#
# Pinned by digest, not tag, because the spec requires it: a tag is a mutable
# pointer and "the object holding it runs with an nsec". This is the multi-arch
# index digest of buzz-sprig:main, which carries both linux/arm64 and
# linux/amd64 -- the cluster node is ARM64.
FROM ghcr.io/block/buzz-sprig@sha256:52dbf83083036a4794ebd70201d0b84a4c858fdcbe88743f150fa8659ae8cc39

# Set by buildx per platform. The cluster node is arm64; amd64 is built so the
# image is usable from a laptop for debugging.
ARG TARGETARCH

# The base image runs as the unprivileged `agent` user; installs need root, and
# the final USER switches back. Never leave this image running as root.
USER root

# npm is needed only to install; it stays because `claude-agent-acp` resolves
# its own dependency tree at runtime.
RUN apk add --no-cache nodejs npm \
 && npm install -g --no-fund --no-audit \
      @agentclientprotocol/claude-agent-acp@0.88.0 \
 && npm cache clean --force \
 && rm -rf /root/.npm /tmp/*

# jq comes from Alpine main, so apk's signed index covers it. The rest are
# upstream release binaries: Alpine's kubectl trails the k0s server by several
# minors, which is outside the ±1 kubectl skew policy.
RUN apk add --no-cache jq

# Versions are pinned deliberately, not floated:
#   kubectl matches the k0s server exactly (v1.36.4+k0s).
#   flux matches `flux_version` in roles/flux/defaults/main.yml, so the CLI in
#     this image and the one Ansible puts on the host cannot drift.
#   helm stays on 3.x to match helm-controller v1.4.5's Helm 3 release storage;
#     Helm 4 is out but nothing in this cluster speaks it yet.
ARG KUBECTL_VERSION=v1.36.4
ARG HELM_VERSION=v3.22.0
ARG FLUX_VERSION=v2.7.5
ARG YQ_VERSION=v4.54.1

# Checksums are per-arch and verified at build time. Upstream publishes all of
# these (kubectl `.sha256`, helm `.sha256sum`, flux `checksums.txt`, yq
# `checksums` column 18); the yq values were additionally reproduced locally
# against that file. An unpinned curl|tar into a cluster-admin image is exactly
# the supply-chain hole the digest pin above exists to close.
RUN set -eux; \
    case "$TARGETARCH" in \
      amd64) \
        kubectl_sha=8b8f088da2dab964f853b38464033b1be15ede2839eca751482357c45abdd05a; \
        helm_sha=1e4ab49e429626cf6c6958d914248b78c9730803c2751b87627e171dc800e7bb; \
        flux_sha=1e92141e8498289e4b27411385aeb18396053176cf297b0cb99abd6ca8293e75; \
        yq_sha=e68a456f90c577af3fe4960184b3a3cf5c461e0348407c10f107da3a5fec8972; \
        ;; \
      arm64) \
        kubectl_sha=0ecf44450ee6063bf19dd166a103ee6df4a9034455c2abce626e6eea657d73fb; \
        helm_sha=f14e804dfee240f55525b667488fe9adca349e63e00c9af634c0beb1421ac310; \
        flux_sha=89d3ebb47ee5f7a0def33217e8dcb885e0bec41d01d0e23fc84e9aba0416c24e; \
        yq_sha=8c27f6e7476fb5acefb9352e3d30f6bc2dc93f1956eb92e8da727173fb7ec6d3; \
        ;; \
      *) echo "unsupported TARGETARCH: $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    cd "$(mktemp -d)"; \
    \
    curl -fsSLo kubectl \
      "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl"; \
    echo "${kubectl_sha}  kubectl" | sha256sum -c -; \
    install -m 0755 kubectl /usr/local/bin/kubectl; \
    \
    curl -fsSLo helm.tgz \
      "https://get.helm.sh/helm-${HELM_VERSION}-linux-${TARGETARCH}.tar.gz"; \
    echo "${helm_sha}  helm.tgz" | sha256sum -c -; \
    tar xzf helm.tgz; \
    install -m 0755 "linux-${TARGETARCH}/helm" /usr/local/bin/helm; \
    \
    curl -fsSLo flux.tgz \
      "https://github.com/fluxcd/flux2/releases/download/${FLUX_VERSION}/flux_${FLUX_VERSION#v}_linux_${TARGETARCH}.tar.gz"; \
    echo "${flux_sha}  flux.tgz" | sha256sum -c -; \
    tar xzf flux.tgz; \
    install -m 0755 flux /usr/local/bin/flux; \
    \
    curl -fsSLo yq.tgz \
      "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${TARGETARCH}.tar.gz"; \
    echo "${yq_sha}  yq.tgz" | sha256sum -c -; \
    tar xzf yq.tgz; \
    install -m 0755 "./yq_linux_${TARGETARCH}" /usr/local/bin/yq; \
    \
    cd /; rm -rf /tmp/*

# kubectl, unlike client-go, does NOT fall back to in-cluster config -- without
# a kubeconfig it tries localhost:8080 and fails. This one wires it to the
# projected ServiceAccount: `tokenFile` (not `token`) so kubectl re-reads the
# file as the kubelet rotates it, rather than pinning an expiring bearer token.
# helm and flux read KUBECONFIG too, so all three are covered by this.
#
# It lives outside $HOME on purpose: the Deployment mounts an emptyDir over
# /home/agent, which would mask anything baked into ~/.kube.
RUN mkdir -p /etc/buzz-agent \
 && printf '%s\n' \
      'apiVersion: v1' \
      'kind: Config' \
      'current-context: in-cluster' \
      'clusters:' \
      '  - name: in-cluster' \
      '    cluster:' \
      '      server: https://kubernetes.default.svc' \
      '      certificate-authority: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt' \
      'users:' \
      '  - name: in-cluster' \
      '    user:' \
      '      tokenFile: /var/run/secrets/kubernetes.io/serviceaccount/token' \
      'contexts:' \
      '  - name: in-cluster' \
      '    context:' \
      '      cluster: in-cluster' \
      '      user: in-cluster' \
      '      namespace: default' \
    > /etc/buzz-agent/kubeconfig \
 && chmod 0444 /etc/buzz-agent/kubeconfig
ENV KUBECONFIG=/etc/buzz-agent/kubeconfig

# Fail the build rather than ship an image whose agent command is missing: the
# harness resolves BUZZ_ACP_AGENT_COMMAND against this image's PATH, and a
# missing binary would surface only as a dead agent at runtime. The cluster
# tools are *executed*, not just located -- buildx runs the arm64 stage under
# QEMU, so this is a real arm64/musl check and catches a glibc-only build.
RUN command -v claude-agent-acp >/dev/null \
 && command -v buzz-acp >/dev/null \
 && command -v buzz-dev-mcp >/dev/null \
 && node --version \
 && kubectl version --client=true \
 && helm version --short \
 && flux --version \
 && jq --version \
 && yq --version

USER agent
WORKDIR /home/agent

# Inherited from buzz-sprig and restated so a base-image change cannot silently
# drop it: the harness must be PID 1 so it receives SIGTERM and can complete its
# graceful shutdown (presence -> offline) inside terminationGracePeriodSeconds.
ENTRYPOINT ["/usr/local/bin/sprig-entrypoint"]
