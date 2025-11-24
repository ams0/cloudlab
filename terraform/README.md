# Oracle Single VM Terraform

This directory contains a minimal Terraform configuration that provisions the
networking components and a single Compute instance in Oracle Cloud Infrastructure
(OCI). The VM is prepared for subsequent configuration through the Ansible playbook
in the repository.

## Files

- `main.tf` – provider setup plus VCN, subnet, security list, and the compute instance
- `variables.tf` – input variable declarations with documentation
- `outputs.tf` – exposes instance identifiers and IP addresses
- `terraform.tfvars.example` – sample variable file you can copy and customize

## Prerequisites

1. Terraform v1.5 or newer.
2. OCI user credentials with permission to manage networking and compute in the
   target compartment. Populate the following values beforehand:
   - Tenancy OCID, user OCID, compartment OCID
   - Region identifier (e.g. `eu-frankfurt-1`)
   - API key fingerprint and the path to the corresponding private key
   - Image OCID for the OS you want to boot
   - SSH public key string to inject into the instance metadata

## Usage

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars and provide the required OCIDs, region, and image
terraform init
terraform plan
terraform apply
```

The outputs display the instance OCID as well as its public and private IP
addresses. Use the private IP address when updating `inventory.ini` for Ansible
management. If you keep the generated state file inside this directory, remember
to secure it appropriately because it contains sensitive information.
