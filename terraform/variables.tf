variable "tenancy_ocid" {
  description = "OCID of the tenancy (root compartment)."
  type        = string
}

variable "user_ocid" {
  description = "OCID of the IAM user whose API key is used."
  type        = string
}

variable "compartment_ocid" {
  description = "OCID of the compartment where resources will be created."
  type        = string
}

variable "region" {
  description = "OCI region identifier, e.g. eu-frankfurt-1."
  type        = string
}

variable "api_fingerprint" {
  description = "Fingerprint of the OCI API key."
  type        = string
}

variable "api_private_key_path" {
  description = "Path to the private key that matches the fingerprint."
  type        = string
}

variable "availability_domain" {
  description = "Name of the availability domain. Leave empty to pick the first AD in the region."
  type        = string
  default     = null
}

variable "project_name" {
  description = "Name used for tagging and resource names."
  type        = string
  default     = "cloudlab"
}

variable "freeform_tags" {
  description = "Additional freeform tags applied to every resource."
  type        = map(string)
  default     = {}
}

variable "vcn_cidr" {
  description = "CIDR block for the new VCN."
  type        = string
  default     = "10.20.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the public subnet."
  type        = string
  default     = "10.20.10.0/24"
}

variable "ssh_allowed_cidrs" {
  description = "List of CIDRs that are allowed to reach the instance over SSH."
  type        = list(string)
  default     = ["95.99.46.198/32"]
}

variable "extra_ingress_rules" {
  description = "Optional extra ingress rules for the security list."
  type = list(object({
    protocol    = string
    source      = string
    description = optional(string)
    tcp_options = optional(object({
      min = number
      max = number
    }))
    udp_options = optional(object({
      min = number
      max = number
    }))
  }))
  default = []
}

variable "assign_public_ip" {
  description = "Whether to assign a public IP to the instance."
  type        = bool
  default     = true
}

variable "instance_display_name" {
  description = "Display name for the compute instance."
  type        = string
  default     = "oracle-singlehost"
}

variable "instance_shape" {
  description = "Compute shape name (e.g. VM.Standard.E5.Flex)."
  type        = string
  default     = "VM.Standard.E5.Flex"
}

variable "instance_ocpus" {
  description = "Number of OCPUs (only for flex shapes)."
  type        = number
  default     = null
}

variable "instance_memory_in_gbs" {
  description = "Amount of memory in GBs (only for flex shapes)."
  type        = number
  default     = null
}

variable "instance_image_ocid" {
  description = "OCID of the OS image to boot from."
  type        = string
}

variable "boot_volume_size_in_gbs" {
  description = "Size of the boot volume."
  type        = number
  default     = 50
}

variable "ssh_public_key" {
  description = "SSH public key string that is injected into the instance metadata."
  type        = string
}

variable "cloud_init_template" {
  description = "Optional cloud-init user-data template."
  type        = string
  default     = ""
}
