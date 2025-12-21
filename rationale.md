# Project Rationale: CloudLab

## Executive Summary

This project implements a **production-grade, single-node Kubernetes platform** on Oracle Cloud Infrastructure (OCI) free tier using infrastructure-as-code principles. It combines Terraform for cloud provisioning and Ansible for configuration management to create a fully automated, secure, and observable edge computing environment.

## Project Purpose

### Primary Goals
1. **Cost-Effective Kubernetes**: Leverage Oracle Cloud's free tier (ARM-based VM.Standard.E5.Flex) to run a production-ready Kubernetes cluster
2. **Full Automation**: Achieve complete infrastructure-as-code from cloud resources to application deployment
3. **Production Standards**: Implement enterprise-grade monitoring, backup, security, and networking from day one
4. **Edge/IoT Platform**: Create a lightweight yet capable platform suitable for edge computing workloads

### Use Cases
- Personal Kubernetes learning and experimentation
- Lightweight microservices hosting
- Edge computing workloads
- IoT data collection and processing
- CI/CD experimentation platform
- Development environment for cloud-native applications

## Architectural Decisions

### 1. Terraform for Infrastructure Provisioning

**Choice**: Use Terraform to manage OCI resources

**Rationale**:
- **Declarative IaC**: Infrastructure defined as code, version-controlled
- **Idempotent**: Safe to re-run without side effects
- **OCI Provider Maturity**: Well-maintained official provider (~5.32)
- **State Management**: Tracks resource lifecycle and dependencies
- **Automation**: Generates Ansible inventory automatically from outputs

**Key Infrastructure Decisions**:
- **IPv6 Support**: Future-proofing network connectivity
- **Flexible Security Lists**: Dynamic ingress rules for changing requirements
- **DNS Labels**: Automatic DNS naming within OCI VCN
- **Public IP Assignment**: Direct internet accessibility without NAT

### 2. Ansible for Configuration Management

**Choice**: Use Ansible over alternatives (Chef, Puppet, SaltStack)

**Rationale**:
- **Agentless**: No daemon installation on target hosts (SSH-based)
- **Simple Syntax**: YAML-based, human-readable playbooks
- **Role-Based Organization**: Modular, reusable components
- **Large Ecosystem**: Extensive module library for common tasks
- **Vault Integration**: Built-in secret management
- **Idempotent Modules**: Safe repeated execution

**Role-Based Architecture Benefits**:
- **Separation of Concerns**: Each role handles one responsibility
- **Reusability**: Roles can be shared across projects
- **Testability**: Individual roles can be tested in isolation
- **Tag-Based Execution**: Run specific components selectively
- **Clear Dependencies**: Explicit role ordering in site.yml

### 3. k0s Kubernetes Distribution (Deprecated → k3s)

**Original Choice**: k0s for lightweight Kubernetes

**Rationale for k0s**:
- **Single Binary**: Simple installation and updates
- **No External Dependencies**: Batteries-included distribution
- **ARM64 Support**: Native support for Oracle's Ampere processors
- **Small Footprint**: Efficient resource usage on free tier
- **Production-Ready**: Backed by Mirantis

**Why Switching to k3s**:
- **CNI Issues**: k0s networking problems on this specific setup
- **Better ARM Support**: k3s more mature on ARM architecture
- **Simpler Operations**: k3s has fewer moving parts
- **Community Momentum**: Larger user base and ecosystem

### 4. Docker as Container Runtime

**Choice**: Docker CE over containerd-only

**Rationale**:
- **Developer Familiarity**: Most developers know Docker
- **CLI Tools**: docker-compose and docker buildx included
- **Debugging**: Easier container inspection and troubleshooting
- **Image Building**: Built-in build capabilities
- **Compatibility**: Works seamlessly with k0s/k3s

### 5. BorgBackup for Disaster Recovery

**Choice**: BorgBackup over Restic, rsync, or cloud-native solutions

**Rationale**:
- **Deduplication**: Efficient storage with block-level dedup
- **Compression**: LZMA compression reduces bandwidth and storage
- **Encryption**: Built-in repokey-blake2 encryption
- **Incremental**: Fast incremental backups
- **Mature**: Proven in production for many years
- **Open Source**: No vendor lock-in

**Backup Strategy**:
- **Daily Schedule**: 02:30 automated via systemd timers
- **Retention Policy**: 7 daily, 4 weekly, 6 monthly, 1 yearly
- **Remote Storage**: Synology NAS via SSH (off-site backup)
- **Critical Paths**: /home, /root, /etc, /usr/local

### 6. Tailscale for Secure Networking

**Choice**: Tailscale over WireGuard, OpenVPN, or IPSec

**Rationale**:
- **Zero Configuration**: Automatic mesh network setup
- **NAT Traversal**: Works behind firewalls without port forwarding
- **Modern Cryptography**: Built on WireGuard
- **ACL Management**: Centralized access control
- **Multi-Platform**: Access from any device
- **Free Tier**: Sufficient for personal use

**Use Cases**:
- Secure remote access without exposing SSH publicly
- Private kubectl access to Kubernetes API
- Mesh networking between multiple edge nodes
- Backup traffic over private network

### 7. Datadog for Observability

**Choice**: Datadog over Prometheus/Grafana, ELK, or cloud-native solutions

**Rationale**:
- **Unified Platform**: Metrics, logs, traces in one place
- **Low Overhead**: Lightweight agent suitable for small VMs
- **Managed Service**: No operational burden of self-hosting
- **Free Tier**: Sufficient for single-host monitoring
- **ARM Support**: Native ARM64 agent available

**Monitoring Strategy**:
- **System Metrics**: CPU, memory, disk, network
- **Process Monitoring**: Track key services (k0s, docker, etc.)
- **Log Collection**: Centralized journald logs
- **Custom Tags**: Filtering by environment, role, managed_by

### 8. fail2ban for Security

**Choice**: fail2ban over cloud-native firewalls or manual iptables

**Rationale**:
- **Proven Solution**: Battle-tested SSH protection
- **Dynamic Blocking**: Automatically bans malicious IPs
- **Low Resource Usage**: Minimal CPU/memory footprint
- **Logging Integration**: Works with systemd journal
- **Configurable**: Rate limits and ban durations customizable

### 9. Flux CD for GitOps (Planned)

**Choice**: Flux over ArgoCD, Jenkins, or manual deployments

**Rationale**:
- **GitOps Native**: Kubernetes resources in Git as source of truth
- **Declarative**: Desired state defined, Flux reconciles
- **CNCF Project**: Cloud Native Computing Foundation graduated project
- **Kustomize Support**: Native integration with Kustomize
- **Lightweight**: Suitable for single-node clusters

**Current Status**: Disabled pending k3s stability

## Technology Stack Rationale

### Operating System: Ubuntu 24.04 LTS ARM64

**Rationale**:
- **LTS Support**: 5 years of security updates
- **ARM64 Optimization**: Native support for Ampere processors
- **Package Availability**: Largest ARM package ecosystem
- **Community**: Extensive documentation and community support
- **Cloud-Init**: Built-in cloud initialization support

### Language Choices

**Terraform HCL**:
- Domain-specific language for infrastructure
- Type-safe with validation
- Extensive provider ecosystem

**Ansible YAML**:
- Human-readable configuration
- No programming required
- Jinja2 templating for dynamic values

**Bash Scripts**:
- System integration (borg-backup.sh, deploy.sh)
- Portable across Unix-like systems
- Direct system access

### Security Architecture

**Defense in Depth**:
1. **Network Layer**: Oracle Cloud Security Lists + iptables
2. **SSH Hardening**: Key-based auth, fail2ban protection
3. **Principle of Least Privilege**: Minimal open ports
4. **Secret Management**: Ansible Vault for credentials
5. **Automated Updates**: APT package management
6. **Monitoring**: Real-time security event detection

**Security Decisions**:
- **SSH Restriction**: Only from specific IP (95.99.46.198/32)
- **No Password Auth**: SSH keys only
- **Tailscale Overlay**: Additional network security layer
- **Encrypted Backups**: BorgBackup encryption at rest
- **TLS Certificates**: Kubernetes API with proper SANs

## Project Structure Rationale

### Directory Organization

```
cloudlab/
├── terraform/          # Infrastructure layer (cloud resources)
├── roles/              # Configuration layer (system setup)
├── group_vars/         # Environment-specific configuration
├── gitops/            # Application layer (Kubernetes manifests)
└── site.yml           # Orchestration (execution order)
```

**Benefits**:
- **Clear Separation**: Infrastructure vs. configuration vs. applications
- **Reusability**: Roles can be extracted and shared
- **Testability**: Each layer can be tested independently
- **Scalability**: Easy to add new roles or infrastructure

### Configuration Management

**Group Variables** (`group_vars/oracle_hosts/`):
- **main.yml**: Non-sensitive configuration
- **vault.yml**: Encrypted secrets (API keys, passwords)
- **packages.yml**: Package lists (maintainability)

**Benefits**:
- **DRY Principle**: Configuration defined once, used everywhere
- **Security**: Secrets encrypted with Ansible Vault
- **Maintainability**: Central location for updates
- **Version Control**: Safe to commit (vault encrypted)

## Automation Workflow Rationale

### Two-Stage Deployment

**Stage 1: Terraform**
```bash
cd terraform && terraform apply
```
- Provisions cloud infrastructure
- Generates inventory.ini automatically
- Outputs instance IPs and IDs

**Stage 2: Ansible**
```bash
ansible-playbook site.yml
```
- Configures system and software
- Deploys Kubernetes and applications
- Sets up monitoring and backups

**Rationale**:
- **Clean Separation**: Infrastructure vs. configuration
- **Independent Lifecycles**: Rebuild config without destroying infrastructure
- **Faster Iteration**: Only run Ansible for config changes
- **State Management**: Terraform state for infrastructure, Ansible for configuration

### Tag-Based Selective Execution

**Example**:
```bash
ansible-playbook site.yml --tags docker
ansible-playbook site.yml --tags backup,monitoring
```

**Rationale**:
- **Faster Development**: Only run changed components
- **Debugging**: Isolate problematic roles
- **Production Updates**: Deploy specific changes without full run
- **Cost Optimization**: Minimize execution time and API calls

## Scalability Considerations

### Current Limitations
- **Single Node**: Not highly available
- **Free Tier**: Resource constraints (4 OCPU, 24GB RAM)
- **Single Region**: No geographic redundancy
- **Manual Scaling**: No auto-scaling configured

### Future Scalability Path
1. **Multi-Node**: Add worker nodes with same Ansible roles
2. **Load Balancing**: MetalLB for service exposure
3. **Storage**: Persistent volumes with cloud-native CSI drivers
4. **Multi-Region**: Terraform modules for multiple regions
5. **Auto-Scaling**: HPA and cluster autoscaler

### Current Design Benefits Scalability
- **Role-Based**: Roles work on single or multiple hosts
- **Inventory Groups**: Easy to add node groups
- **Idempotent**: Safe to add/remove nodes repeatedly
- **GitOps Ready**: Flux can manage multi-cluster

## Cost Optimization

### Free Tier Maximization
- **Oracle Cloud Free Tier**: VM.Standard.E5.Flex (4 OCPU, 24GB)
- **Lightweight k0s/k3s**: Lower overhead than full Kubernetes
- **Efficient Monitoring**: Datadog free tier (5 hosts)
- **Tailscale**: Free for personal use (up to 100 devices)
- **Remote Backup**: Use existing NAS, no cloud storage costs

### Resource Efficiency
- **Swap Disabled**: Required for Kubernetes, reduces I/O
- **ARM Architecture**: Better performance per watt
- **Systemd Timers**: Replace cron for lower overhead
- **Docker over Podman**: Smaller memory footprint for k0s

## Lessons Learned

### What Worked Well
1. **Terraform Auto-Inventory**: Eliminates manual inventory management
2. **Ansible Vault**: Simple secret management without external tools
3. **BorgBackup**: Reliable, efficient backups to NAS
4. **Tailscale**: Seamless secure access without VPN complexity
5. **Role Modularity**: Easy to enable/disable components

### What Didn't Work
1. **k0s CNI Issues**: Networking problems on this specific setup
2. **Flux Timing**: Needed to disable until k3s stable
3. **Certificate Management**: Required custom regeneration logic

### Improvements Made
1. **Switch to k3s**: Better ARM support and stability
2. **Idempotent Checks**: Prevent unnecessary reinstalls
3. **Async Operations**: Handle long-running k0s installations
4. **Firewall Rules**: Both OCI Security Lists and iptables

## Future Roadmap

### Short Term
- [ ] Complete k3s migration from k0s
- [ ] Re-enable Flux GitOps automation
- [ ] Add MetalLB load balancer
- [ ] Implement cert-manager for TLS automation

### Medium Term
- [ ] Add observability stack (Prometheus/Grafana)
- [ ] Implement persistent storage with Longhorn
- [ ] Add ingress controller (Traefik or nginx)
- [ ] Create CI/CD pipeline for application deployments

### Long Term
- [ ] Multi-node cluster support
- [ ] Multi-region deployment with Terraform modules
- [ ] Advanced networking (Cilium, network policies)
- [ ] Service mesh (Linkerd) integration

## Conclusion

This project demonstrates **enterprise-grade DevOps practices applied to a single-node edge computing platform**. The architecture balances:

- **Simplicity**: Single-node, free tier, lightweight components
- **Production Standards**: Monitoring, backup, security, automation
- **Scalability**: Designed to grow from single node to multi-region cluster
- **Cost Efficiency**: Maximizes free tier resources
- **Maintainability**: Infrastructure-as-code with clear organization

The combination of Terraform + Ansible + Kubernetes + GitOps provides a **solid foundation for cloud-native application development** while remaining accessible and cost-effective for personal or small-scale production use.
