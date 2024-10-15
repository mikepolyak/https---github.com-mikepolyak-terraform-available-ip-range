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
  
  # Calculate the existing subnet number within the VNet
  vnet_decimal = [for octet in split(".", split("/", var.vnet_cidr)[0]): tonumber(octet)]
  existing_subnet_decimal = [for octet in split(".", split("/", var.existing_subnet_cidr)[0]): tonumber(octet)]
  existing_subnet_number = (
    (local.existing_subnet_decimal[0] - local.vnet_decimal[0]) * pow(256, 3) +
    (local.existing_subnet_decimal[1] - local.vnet_decimal[1]) * pow(256, 2) +
    (local.existing_subnet_decimal[2] - local.vnet_decimal[2]) * 256 +
    (local.existing_subnet_decimal[3] - local.vnet_decimal[3])
  ) / pow(2, local.existing_subnet_prefix_length - local.vnet_prefix_length)

  # Calculate the next available subnet number
  next_subnet_number = local.existing_subnet_number + 1
  
  # Ensure the next_subnet_number is within the valid range
  max_subnet_number = pow(2, var.new_subnet_prefix_length - local.vnet_prefix_length) - 1
  valid_next_subnet_number = min(local.next_subnet_number, local.max_subnet_number)

  next_subnet = cidrsubnet(var.vnet_cidr, var.new_subnet_prefix_length - local.vnet_prefix_length, local.valid_next_subnet_number)

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