# vnet_subnet_module/vnet_subnet_module.tf

terraform {
  required_version = ">= 0.12"
}

variable "vnet_cidr" {
  description = "The CIDR block for the VNet (e.g., '10.0.0.0/16')"
  type        = string
}

variable "existing_subnet_cidr" {
  description = "The CIDR block for an existing subnet (e.g., '10.0.0.0/24')"
  type        = string
}

variable "new_subnet_prefix_length" {
  description = "The prefix length for the new subnet (e.g., 24 for a /24 subnet)"
  type        = number
}

locals {
  vnet_prefix_length = tonumber(split("/", var.vnet_cidr)[1])
  existing_subnet_prefix_length = tonumber(split("/", var.existing_subnet_cidr)[1])
  
  # Convert IP to number
  ip_to_number = {
    vnet = sum([
      for i, v in split(".", split("/", var.vnet_cidr)[0]) :
      tonumber(v) * pow(256, 3 - i)
    ])
    existing_subnet = sum([
      for i, v in split(".", split("/", var.existing_subnet_cidr)[0]) :
      tonumber(v) * pow(256, 3 - i)
    ])
  }
  
  # Calculate the start and end of the existing subnet
  existing_subnet_start = local.ip_to_number.existing_subnet
  existing_subnet_end = local.existing_subnet_start + pow(2, 32 - local.existing_subnet_prefix_length) - 1
  
  # Calculate the size of the new subnet
  new_subnet_size = pow(2, 32 - var.new_subnet_prefix_length)
  
  # Find the first available subnet
  next_subnet_start = local.ip_to_number.vnet + floor((
    local.existing_subnet_start - local.ip_to_number.vnet
  ) / local.new_subnet_size) * local.new_subnet_size
  
  # If the calculated start overlaps with the existing subnet, move to the next available space
  next_subnet_start_adjusted = local.next_subnet_start < local.existing_subnet_start ? (
    local.next_subnet_start
  ) : (
    local.existing_subnet_end + 1 - (local.existing_subnet_end + 1) % local.new_subnet_size
  )
  
  # Calculate the next available subnet
  next_subnet = cidrsubnet(
    var.vnet_cidr,
    var.new_subnet_prefix_length - local.vnet_prefix_length,
    (local.next_subnet_start_adjusted - local.ip_to_number.vnet) / local.new_subnet_size
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

output "existing_subnet_cidr" {
  description = "The CIDR block of the existing subnet"
  value       = var.existing_subnet_cidr
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