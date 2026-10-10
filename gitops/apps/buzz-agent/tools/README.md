# Agent ownership attestation tools

`bip340.py` is the BIP-340 Schnorr reference implementation, vendored because
the agent's ownership attestation has to be signed offline with the owner key
and `coincurve` does not build on this machine. It was validated against the
official BIP-340 test vectors (keygen, signing and verification for vectors
0-2, plus rejection of a forged signature) before being used on a real key.

It was used for two one-off publications that make the agent a *discoverable
owned agent* rather than a bare relay key:

1. **The NIP-OA `auth` tag** on the agent's kind:0 profile —
   `["auth", <owner pubkey>, <conditions>, <sig>]`, where the signature is over
   `SHA256("nostr:agent-auth:" || <agent pubkey> || ":" || <conditions>)` with
   empty conditions. The tag is in `deployment.yaml` as `BUZZ_AUTH_TAG`; the
   harness republishes the profile carrying it.

2. **An owner-authored kind 30177 policy event**, `d` tag = agent pubkey,
   content `{name, persona_id, parallelism, respond_to}` — matching the shape
   the desktop writes for its own agents. Published to the relay's
   `POST /events` bridge with NIP-98 auth. This event is relay state, not
   reconcilable from Git; re-publish it if the relay database is ever rebuilt.

Both are owner-signed, so reproducing them requires the owner's private key,
which is deliberately not in this repository or the cluster.
