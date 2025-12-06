terraform {
  required_version = ">= 1.5.0"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 5.32"
    }
  }
}

provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.api_fingerprint
  private_key_path = var.api_private_key_path
  region           = var.region
}

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

locals {
  availability_domain = coalesce(
    var.availability_domain,
    try(data.oci_identity_availability_domains.ads.availability_domains[0].name, null)
  )

  ssh_authorized_keys = chomp(var.ssh_public_key)

  common_tags = merge(
    {
      "Managed-By" = "terraform"
      "Project"    = var.project_name
    },
    var.freeform_tags
  )

  dns_label_source = replace(lower(var.project_name), "/[^a-z0-9]/", "")
  vcn_dns_label    = substr(length(local.dns_label_source) > 0 ? local.dns_label_source : "tfhost", 0, 15)
  subnet_dns_label = substr("${local.vcn_dns_label}sn", 0, 15)
  host_dns_label   = substr("${local.vcn_dns_label}vm", 0, 15)
}

resource "oci_core_virtual_network" "this" {
  cidr_block     = var.vcn_cidr
  compartment_id = var.compartment_ocid
  display_name   = "${var.project_name}-vcn"
  dns_label      = local.vcn_dns_label
  is_ipv6enabled = true

  freeform_tags = local.common_tags
}

resource "oci_core_internet_gateway" "this" {
  compartment_id = var.compartment_ocid
  display_name   = "${var.project_name}-igw"
  vcn_id         = oci_core_virtual_network.this.id
  enabled        = true

  freeform_tags = local.common_tags
}

resource "oci_core_route_table" "this" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_virtual_network.this.id
  display_name   = "${var.project_name}-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.this.id
  }

  route_rules {
    destination       = "::/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.this.id
  }

  freeform_tags = local.common_tags
}

resource "oci_core_security_list" "this" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_virtual_network.this.id
  display_name   = "${var.project_name}-sl"

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  egress_security_rules {
    destination = "::/0"
    protocol    = "all"
  }

  # Allow ICMPv4 ping
  ingress_security_rules {
    protocol    = "1"
    source      = "0.0.0.0/0"
    description = "ICMPv4 ping"

    icmp_options {
      type = 8
      code = 0
    }
  }

  # Allow ICMPv6 ping
  ingress_security_rules {
    protocol    = "58"
    source      = "::/0"
    description = "ICMPv6 ping"

    icmp_options {
      type = 128
      code = 0
    }
  }

  dynamic "ingress_security_rules" {
    for_each = var.ssh_allowed_cidrs
    content {
      protocol = "6"

      tcp_options {
        min = 22
        max = 22
      }

      source = ingress_security_rules.value
    }
  }

  dynamic "ingress_security_rules" {
    for_each = var.ssh_allowed_cidrs
    content {
      protocol    = "6"
      source      = ingress_security_rules.value
      description = "Kubernetes API Server"

      tcp_options {
        min = 6443
        max = 6443
      }
    }
  }

  # Allow SSH over IPv6
  ingress_security_rules {
    protocol    = "6"
    source      = "::/0"
    description = "SSH over IPv6"

    tcp_options {
      min = 22
      max = 22
    }
  }

  # Allow k8s API over IPv6
  ingress_security_rules {
    protocol    = "6"
    source      = "::/0"
    description = "Kubernetes API Server over IPv6"

    tcp_options {
      min = 6443
      max = 6443
    }
  }

  # Allow HTTP
  ingress_security_rules {
    protocol    = "6"
    source      = "0.0.0.0/0"
    description = "HTTP"

    tcp_options {
      min = 80
      max = 80
    }
  }

  # Allow HTTP over IPv6
  ingress_security_rules {
    protocol    = "6"
    source      = "::/0"
    description = "HTTP over IPv6"

    tcp_options {
      min = 80
      max = 80
    }
  }

  # Allow HTTPS
  ingress_security_rules {
    protocol    = "6"
    source      = "0.0.0.0/0"
    description = "HTTPS"

    tcp_options {
      min = 443
      max = 443
    }
  }

  # Allow HTTPS over IPv6
  ingress_security_rules {
    protocol    = "6"
    source      = "::/0"
    description = "HTTPS over IPv6"

    tcp_options {
      min = 443
      max = 443
    }
  }

  # Allow port 8000
  ingress_security_rules {
    protocol    = "6"
    source      = "0.0.0.0/0"
    description = "Port 8000"

    tcp_options {
      min = 8000
      max = 8000
    }
  }

  # Allow port 8000 over IPv6
  ingress_security_rules {
    protocol    = "6"
    source      = "::/0"
    description = "Port 8000 over IPv6"

    tcp_options {
      min = 8000
      max = 8000
    }
  }

  # Allow port 9000
  ingress_security_rules {
    protocol    = "6"
    source      = "0.0.0.0/0"
    description = "Port 9000"

    tcp_options {
      min = 9000
      max = 9000
    }
  }

  # Allow port 9000 over IPv6
  ingress_security_rules {
    protocol    = "6"
    source      = "::/0"
    description = "Port 9000 over IPv6"

    tcp_options {
      min = 9000
      max = 9000
    }
  }

  dynamic "ingress_security_rules" {
    for_each = var.extra_ingress_rules
    content {
      protocol    = ingress_security_rules.value.protocol
      source      = ingress_security_rules.value.source
      description = lookup(ingress_security_rules.value, "description", null)

      dynamic "tcp_options" {
        for_each = lookup(ingress_security_rules.value, "tcp_options", null) != null ? [lookup(ingress_security_rules.value, "tcp_options", null)] : []
        content {
          min = tcp_options.value.min
          max = tcp_options.value.max
        }
      }

      dynamic "udp_options" {
        for_each = lookup(ingress_security_rules.value, "udp_options", null) != null ? [lookup(ingress_security_rules.value, "udp_options", null)] : []
        content {
          min = udp_options.value.min
          max = udp_options.value.max
        }
      }
    }
  }

  freeform_tags = local.common_tags
}

resource "oci_core_subnet" "this" {
  cidr_block        = var.subnet_cidr
  compartment_id    = var.compartment_ocid
  display_name      = "${var.project_name}-subnet"
  dns_label         = local.subnet_dns_label
  vcn_id            = oci_core_virtual_network.this.id
  route_table_id    = oci_core_route_table.this.id
  security_list_ids = [oci_core_security_list.this.id]
  dhcp_options_id   = oci_core_virtual_network.this.default_dhcp_options_id
  ipv6cidr_block    = cidrsubnet(oci_core_virtual_network.this.ipv6cidr_blocks[0], 8, 1)

  prohibit_public_ip_on_vnic = !var.assign_public_ip

  freeform_tags = local.common_tags
}

resource "oci_core_instance" "this" {
  availability_domain = local.availability_domain
  compartment_id      = var.compartment_ocid
  display_name        = var.instance_display_name
  shape               = var.instance_shape

  dynamic "shape_config" {
    for_each = var.instance_ocpus != null && var.instance_memory_in_gbs != null ? [1] : []
    content {
      ocpus         = var.instance_ocpus
      memory_in_gbs = var.instance_memory_in_gbs
    }
  }

  source_details {
    source_type             = "image"
    source_id               = var.instance_image_ocid
    boot_volume_size_in_gbs = var.boot_volume_size_in_gbs
  }

  create_vnic_details {
    assign_public_ip = var.assign_public_ip
    assign_ipv6ip    = true
    subnet_id        = oci_core_subnet.this.id
    display_name     = "${var.instance_display_name}-vnic"
    hostname_label   = local.host_dns_label
  }

  metadata = merge(
    {
      ssh_authorized_keys = local.ssh_authorized_keys
    },
    length(trimspace(var.cloud_init_template)) > 0 ? {
      user_data = base64encode(var.cloud_init_template)
    } : {}
  )

  freeform_tags = local.common_tags

  lifecycle {
    precondition {
      condition     = try(local.availability_domain != null && local.availability_domain != "", false)
      error_message = "Unable to determine an availability domain. Specify `availability_domain`."
    }
  }
}

resource "local_file" "ansible_inventory" {
  content = <<-EOT
    [oracle_hosts]
    oracle-server ansible_host=${oci_core_instance.this.public_ip}

    [oracle_hosts:vars]
    ansible_user=ubuntu
    ansible_ssh_private_key_file=~/.ssh/oracle
    ansible_python_interpreter=/usr/bin/python3
  EOT

  filename        = "${path.module}/../inventory.ini"
  file_permission = "0644"
}
