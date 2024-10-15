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
  description = "The prefix length for the new subnet (e.g., 25 for a /25 subnet)"
  type        = number
}

locals {
  # Extract the prefix length from the vnet_cidr
  vnet_prefix_length = tonumber(split("/", var.vnet_cidr)[1])

  # Calculate the prefix length difference
  prefix_length_diff = var.new_subnet_prefix_length - local.vnet_prefix_length

  # Break up the range to avoid exceeding Terraform's limit
  potential_subnets = flatten([
    for i in range(0, min(pow(2, local.prefix_length_diff), 1024)) : [
      cidrsubnet(var.vnet_cidr, local.prefix_length_diff, i)
    ]
  ])

  # Convert IP to number for overlap calculations for existing subnets only
  ip_to_number = {
    for ip in distinct(concat(
      [for s in var.existing_subnets_cidr : cidrhost(s, 0)], # Start of existing subnets
      [for s in var.existing_subnets_cidr : cidrhost(s, -1)] # End of existing subnets
    )) :
    ip => sum([for x in split(".", ip) : tonumber(x) * pow(256, 3 - index(split(".", ip), x))])
  }

  # Improved overlap check - no overlap with existing subnets
  subnet_overlaps = [
    for subnet in local.potential_subnets : [
      for existing in var.existing_subnets_cidr :
        (
          local.ip_to_number[cidrhost(existing, 0)] <= sum([for x in split(".", cidrhost(subnet, -1)) : tonumber(x) * pow(256, 3 - index(split(".", cidrhost(subnet, -1)), x))]) &&
          local.ip_to_number[cidrhost(existing, -1)] >= sum([for x in split(".", cidrhost(subnet, 0)) : tonumber(x) * pow(256, 3 - index(split(".", cidrhost(subnet, 0)), x))])
        )
    ]
  ]

  # Find the next available subnet
  next_subnet = [
    for i, overlaps in local.subnet_overlaps :
    local.potential_subnets[i] if !contains(overlaps, true) # Select only subnets with no overlap
  ][0]

  # Generate IP addresses for the new subnet (excluding network and broadcast addresses)
  new_subnet_ip_list = [
    for i in range(1, pow(2, 32 - var.new_subnet_prefix_length) - 1) :
    cidrhost(local.next_subnet, i)
  ]
}

# Outputs

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
