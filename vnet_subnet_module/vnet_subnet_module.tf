# vnet_subnet_module/vnet_subnet_module.tf

terraform {
  required_version = ">= 0.12"
}

variable "vnet_cidr" {
  description = "The CIDR block for the VNet (e.g., '10.0.0.0/16')"
  type        = string
}

variable "existing_subnets_cidr" {
  description = "An array of CIDR blocks for existing subnets (e.g., ['10.0.0.0/24', '10.0.1.0/24'])"
  type        = list(string)
}

variable "new_subnet_prefix_length" {
  description = "The prefix length for the new subnet (e.g., 24 for a /24 subnet)"
  type        = number
}

locals {
  vnet_prefix_length = tonumber(split("/", var.vnet_cidr)[1])
  
  # Convert IP to number
  ip_to_number = {
    vnet = sum([
      for i, v in split(".", split("/", var.vnet_cidr)[0]) :
      tonumber(v) * pow(256, 3 - i)
    ])
    existing_subnets = [
      for subnet_cidr in var.existing_subnets_cidr : {
        start = sum([
          for i, v in split(".", split("/", subnet_cidr)[0]) :
          tonumber(v) * pow(256, 3 - i)
        ])
        end = sum([
          for i, v in split(".", split("/", subnet_cidr)[0]) :
          tonumber(v) * pow(256, 3 - i)
        ]) + pow(2, 32 - tonumber(split("/", subnet_cidr)[1])) - 1
      }
    ]
  }
  
  # Check for overlapping subnets
  subnet_ranges = [
    for subnet in local.ip_to_number.existing_subnets :
    "${subnet.start}-${subnet.end}"
  ]
  
  unique_subnet_ranges = distinct(local.subnet_ranges)
  
  # Ensure no overlapping subnets
  validate_no_overlap = length(local.subnet_ranges) == length(local.unique_subnet_ranges) ? true : tobool("Overlapping subnets detected")
  
  # Find the end of the last existing subnet
  subnet_ends = [for subnet in local.ip_to_number.existing_subnets : subnet.end]
  last_subnet_end = length(local.subnet_ends) > 0 ? max(local.subnet_ends...) : local.ip_to_number.vnet

  # Calculate the size of the new subnet
  new_subnet_size = pow(2, 32 - var.new_subnet_prefix_length)
  
  # Calculate the start of the next available subnet
  next_subnet_start = local.last_subnet_end + 1
  
  # Ensure the next subnet start is aligned with the new subnet size
  aligned_next_subnet_start = local.next_subnet_start + (local.new_subnet_size - local.next_subnet_start % local.new_subnet_size) % local.new_subnet_size
  
  # Calculate the next available subnet
  next_subnet = cidrsubnet(
    var.vnet_cidr,
    var.new_subnet_prefix_length - local.vnet_prefix_length,
    (local.aligned_next_subnet_start - local.ip_to_number.vnet) / local.new_subnet_size
  )

  # Generate IP addresses for the new subnet
  new_subnet_ip_list = [
    for i in range(1, pow(2, 32 - var.new_subnet_prefix_length) - 1) :
    cidrhost(local.next_subnet, i)
  ]
}

output "vnet_cidr" {
  description = "The CIDR block of the VNet"
  value       = var.vnet_cidr
}

output "existing_subnets_cidr" {
  description = "The CIDR blocks of the existing subnets"
  value       = var.existing_subnets_cidr
}

output "next_available_subnet" {
  description = "The CIDR block of the next available subnet"
  value       = local.next_subnet
}

output "new_subnet_ip_addresses" {
  description = "List of all usable IP addresses in the new subnet"
  value       = local.new_subnet_ip_list
}

output "new_subnet_ip_count" {
  description = "Number of usable IP addresses in the new subnet"
  value       = length(local.new_subnet_ip_list)
}