# Traefik Role

Ansible role to deploy and manage Traefik reverse proxy on the server.

## Overview

This role:
- Syncs Traefik configuration files from `ingress/traefik/` to `/home/ubuntu/traefik/`
- Deploys Traefik using Docker Compose
- Manages Let's Encrypt certificates
- Configures routing rules for backend services
- Ensures Traefik is running and healthy

## Dependencies

- Docker role (automatically included)
- community.docker Ansible collection

## Variables

See `defaults/main.yml` for all configurable variables:

- `traefik_dir`: Remote deployment directory (default: `/home/ubuntu/traefik`)
- `traefik_version`: Traefik Docker image version (default: `v2.11`)
- `traefik_acme_email`: Email for Let's Encrypt certificates
- `traefik_dashboard_domain`: Dashboard domain name
- `traefik_backend_domains`: List of domains to route to backend service

## Usage

### Deploy Traefik

```bash
# Deploy with all roles
ansible-playbook -i inventory.ini site.yml

# Deploy only Traefik
ansible-playbook -i inventory.ini site.yml --tags traefik

# Deploy with Docker (dependency)
ansible-playbook -i inventory.ini site.yml --tags docker,traefik
```

### Update Configuration

After modifying files in `ingress/traefik/`, run:

```bash
ansible-playbook -i inventory.ini site.yml --tags traefik
```

The role will:
1. Copy updated configuration files
2. Reload Traefik to apply changes
3. Verify Traefik is healthy

## Files Managed

- `traefik.yml`: Static configuration (entrypoints, providers, ACME)
- `dynamic.yml`: Dynamic configuration (routers, middlewares, services)
- `docker-compose.yml`: Docker Compose deployment configuration
- `acme.json`: Let's Encrypt certificates (created automatically)

## Accessing the Dashboard

Dashboard is available at: `https://traefik.vps.kubespaces.cloud`

Default credentials:
- Username: `admin`
- Password: (configured in `traefik_dashboard_auth` variable)

## Troubleshooting

### Check Traefik status

```bash
# SSH to server
ssh -i ~/.ssh/oracle ubuntu@158.101.222.131

# Check container status
cd /home/ubuntu/traefik
docker compose ps

# View logs
docker compose logs -f traefik
```

### Verify certificates

```bash
# Check acme.json
cat /home/ubuntu/traefik/acme.json | jq
```

### Force restart

```bash
ansible-playbook -i inventory.ini site.yml --tags traefik --extra-vars "force_restart=true"
```
