output "instance_id" {
  description = "OCID of the compute instance."
  value       = oci_core_instance.this.id
}

output "instance_public_ip" {
  description = "Public IP address of the compute instance (empty if disabled)."
  value       = oci_core_instance.this.public_ip
}

output "instance_private_ip" {
  description = "Private IP address of the compute instance."
  value       = oci_core_instance.this.private_ip
}

output "subnet_id" {
  description = "OCID of the created subnet."
  value       = oci_core_subnet.this.id
}

output "vcn_id" {
  description = "OCID of the created VCN."
  value       = oci_core_virtual_network.this.id
}

output "vcn_ipv6_cidr_blocks" {
  description = "IPv6 CIDR blocks assigned to the VCN."
  value       = oci_core_virtual_network.this.ipv6cidr_blocks
}

output "subnet_ipv6_cidr_block" {
  description = "IPv6 CIDR block assigned to the subnet."
  value       = oci_core_subnet.this.ipv6cidr_block
}

output "ansible_inventory" {
  description = "Generated Ansible inventory content."
  value       = <<-EOT
    [oracle_hosts]
    oracle-server ansible_host=${oci_core_instance.this.public_ip}

    [oracle_hosts:vars]
    ansible_user=ubuntu
    ansible_ssh_private_key_file=~/.ssh/oracle
    ansible_python_interpreter=/usr/bin/python3
  EOT
}
