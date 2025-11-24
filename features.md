# Ansible Oracle Host Features

This document tracks all features and configurations implemented for the Oracle host management.

## Implemented Features

### 1. Package Management
- **Role**: `packages`
- **Description**: Installs common system packages
- **Packages**: curl, wget, git, htop, vim, unzip, software-properties-common, apt-transport-https, ca-certificates, gnupg, lsb-release, locales
- **Status**: ✅ Implemented

### 2. Docker
- **Role**: `docker`
- **Description**: Docker CE installation with ARM64 architecture support
- **Features**:
  - ARM64 repository configuration
  - User addition to docker group
  - Automatic architecture detection
- **Status**: ✅ Implemented

### 3. Borg Backup
- **Role**: `borg`
- **Description**: Automated backup solution using BorgBackup
- **Features**:
  - Borg 1.4.1 ARM64 binary installation
  - Remote backup to Synology NAS
  - Systemd timer for scheduled backups (daily at 02:30)
  - SSH key authentication
  - Repository encryption (repokey-blake2)
  - Backup paths: `/home`, `/root`, `/etc`, `/usr/local`
  - Retention policy: 7 daily, 4 weekly, 6 monthly, 1 yearly
  - Remote path configuration for Synology NAS
- **Status**: ✅ Implemented

### 4. Datadog Agent
- **Role**: `datadog`
- **Description**: System monitoring and log collection
- **Features**:
  - ARM64 support via official installation script
  - Custom hostname: `oracle-vps`
  - Log collection via journald (Ubuntu 24.04 systemd)
  - Process monitoring enabled
  - Tags: env:production, role:oracle-host, managed_by:ansible
- **Status**: ✅ Implemented

### 5. Tailscale VPN
- **Role**: `tailscale`
- **Description**: Mesh VPN networking
- **Features**:
  - Automatic installation and configuration
  - Custom hostname: `oracle-oracle-server`
  - Auth key from vault
- **Status**: ✅ Implemented

### 6. Common System Configuration
- **Role**: `common`
- **Description**: Basic system setup
- **Features**:
  - Timezone configuration (UTC)
  - Locale configuration (en_US.UTF-8)
  - Swap disable for Kubernetes compatibility
- **Status**: ✅ Implemented

### 7. Cron Jobs
- **Role**: `cron`
- **Description**: Scheduled task management
- **Status**: ✅ Implemented

## Security Features

### Ansible Vault
- Encrypted storage for sensitive data
- API keys, passwords, and authentication tokens
- File: `group_vars/oracle_hosts/vault.yml`

### SSH Key Management
- Existing SSH key usage for Borg backups (`/home/ubuntu/.ssh/nas`)
- Secure authentication without password storage

### 8. Kubernetes (k3s)
- **Role**: `k3s`
- **Description**: Lightweight Kubernetes cluster using k3s
- **Features**:
  - k3s v1.31.3 with ARM64 support
  - Cilium CNI v1.16.5 with eBPF dataplane
  - Single-node setup optimized for edge/IoT
  - Cluster CIDR: 10.42.0.0/16
  - Service CIDR: 10.43.0.0/16
  - Cilium CLI for management
  - External IP access configured
  - Traefik and ServiceLB disabled
- **Status**: ✅ Implemented

## Removed Features

### Kubernetes (k0s) - REMOVED
- **Role**: `kubernetes` (disabled)
- **Reason**: CNI networking issues, replaced with k3s
- **Status**: ❌ Removed - use `cleanup-k0s.yml` to clean up

### Flux CD GitOps - DISABLED
- **Role**: `flux` (disabled)
- **Reason**: Will be re-enabled after k3s is stable
- **Status**: ⏸️ Temporarily disabled

## Planned Features

- Re-enable Flux CD for GitOps
- MetalLB for load balancing
- Ingress controller configuration

## Architecture Notes

- **Target Platform**: ARM64 (aarch64)
- **OS**: Ubuntu 24.04 (systemd-based)
- **Host**: Oracle Cloud VPS (158.101.195.8)
- **Management**: Single host Ansible configuration

## Configuration Files

- **Inventory**: `inventory.ini`
- **Main Playbook**: `site.yml`
- **Variables**: `group_vars/oracle_hosts/main.yml`
- **Secrets**: `group_vars/oracle_hosts/vault.yml` (encrypted)