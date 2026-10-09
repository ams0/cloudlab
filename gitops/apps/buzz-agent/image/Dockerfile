# Buzz agent runtime: buzz-sprig + Claude Code.
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

# Fail the build rather than ship an image whose agent command is missing: the
# harness resolves BUZZ_ACP_AGENT_COMMAND against this image's PATH, and a
# missing binary would surface only as a dead agent at runtime.
RUN command -v claude-agent-acp >/dev/null \
 && command -v buzz-acp >/dev/null \
 && command -v buzz-dev-mcp >/dev/null \
 && node --version

USER agent
WORKDIR /home/agent

# Inherited from buzz-sprig and restated so a base-image change cannot silently
# drop it: the harness must be PID 1 so it receives SIGTERM and can complete its
# graceful shutdown (presence -> offline) inside terminationGracePeriodSeconds.
ENTRYPOINT ["/usr/local/bin/sprig-entrypoint"]
