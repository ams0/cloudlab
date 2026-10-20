# openGym

Self-hosted gym and body-weight tracker ([DuarteSantos8/openGym](https://github.com/DuarteSantos8/openGym)),
served at https://gym.vps.kubespaces.cloud.

## Design

- **Raw manifests, no HelmRelease** — upstream ships no chart, only example manifests
  (`kubernetes/` in the repo); these are adapted from them.
- **One pod, two containers**: `api` (Node, port 3000) and `web` (nginx, port 8080, proxies
  `/api` to `127.0.0.1:3000`). `NGINX_PORT=8080` because the image runs as uid 101 and
  can't bind below 1024 here.
- **`Recreate` strategy, 1 replica** — the API keeps all data as JSON files on the RWO
  `opengym-pvc`; two API processes must never write at once.
- **No database** — everything (`db.json`, `state-<uid>.json`, session `secret`,
  `vapid.json`, `uploads/`) lives in `/data` on `opengym-pvc`. Back that up; losing
  `secret` signs everyone out.
- **TLS** is terminated by the host Traefik (`gym` router in `ingress/traefik/dynamic.yml`),
  which passkeys require. `RP_ID`/`ORIGIN` must match the hostname exactly.
- `FIRST_USER_ADMIN=1`: the first profile created becomes admin. Signup is open
  otherwise; set `INVITE_ONLY=1` once your profile exists to lock it down.

## Upgrading

Bump both image tags together (api and web of one release belong together); read the
upstream release notes first.
