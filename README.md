# CloudLab Host Management

This Ansible project manages a single Oracle host with comprehensive configuration including packages, cron jobs, and Kubernetes.

## Structure

```
.
├── ansible.cfg           # Ansible configuration
├── inventory.ini         # Host inventory
├── site.yml             # Main playbook
├── group_vars/          # Group variables
│   └── oracle_hosts.yml
└── roles/               # Ansible roles
    ├── common/          # Basic system setup
    ├── packages/        # Package management
    ├── cron/           # Cron job management
    ├── docker/         # Docker installation
    ├── tailscale/      # Tailscale VPN
    ├── borg/           # Borg Backup 2.0
    ├── datadog/        # Datadog monitoring
    └── kubernetes/     # Kubernetes installation
```

## Usage

### Provision the VM (Terraform)

A ready-to-use Terraform configuration lives in `terraform/` and creates the VCN,
subnet, security list, and a single compute instance. Copy
`terraform/terraform.tfvars.example` to `terraform/terraform.tfvars`, fill in your
OCI OCIDs and image information, then run:

```bash
cd terraform
terraform init
terraform apply
```

The Terraform outputs show the instance IP addresses that you can paste into
`inventory.ini` before running Ansible.

### Test connection
```bash
ansible oracle_hosts -m ping
```

### Run full configuration
```bash
ansible-playbook site.yml
```

### Run specific roles
```bash
# Only install packages
ansible-playbook site.yml --tags packages

# Only configure cron jobs
ansible-playbook site.yml --tags cron

# Install Kubernetes (uncomment in site.yml first)
ansible-playbook site.yml --tags kubernetes
```

### Check what would change
```bash
ansible-playbook site.yml --check --diff
```

## Configuration

Edit `group_vars/oracle_hosts.yml` to customize:
- Package lists
- Timezone and locale
- Kubernetes settings
- Cron jobs (add `cron_jobs` variable)

Example configurations:

**Cron jobs:**
```yaml
cron_jobs:
  - name: "System backup"
    minute: "0"
    hour: "2"
    job: "/usr/local/bin/backup.sh"
  - name: "Log cleanup"
    minute: "0"
    hour: "1"
    weekday: "0"
    job: "find /var/log -name '*.log' -mtime +30 -delete"
```

**Borg Backup:**
```yaml
borg_repository: "ssh://backup-user@backup-server.com/~/backups/{{ inventory_hostname }}"
borg_ssh_user: "backup-user"
borg_ssh_host: "backup-server.com"
borg_passphrase: "your-secure-passphrase"  # Use ansible-vault
```

**Tailscale:**
```yaml
tailscale_auth_key: "tskey-auth-xxxxxxxxxxxx"  # Use ansible-vault
tailscale_hostname: "oracle-{{ inventory_hostname }}"
tailscale_accept_routes: true
```

**Datadog:**
```yaml
datadog_api_key: "your-datadog-api-key"  # Use ansible-vault
datadog_tags:
  - "env:production"
  - "role:oracle-host"
datadog_logs_enabled: true
datadog_process_agent_enabled: true
```
