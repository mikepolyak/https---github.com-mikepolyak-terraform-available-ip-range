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
  
  # Sort existing subnets
  sorted_subnets = sort([
    for subnet in local.ip_to_number.existing_subnets :
    subnet.start
  ])

  # Calculate the size of the new subnet
  new_subnet_size = pow(2, 32 - var.new_subnet_prefix_length)
  
  # Find gaps between subnets
  subnet_gaps = concat(
    [{ start = local.ip_to_number.vnet, end = local.sorted_subnets[0] - 1 }],
    [
      for i in range(length(local.sorted_subnets) - 1) : {
        start = local.ip_to_number.existing_subnets[index(local.sorted_subnets, local.sorted_subnets[i])].end + 1
        end = local.ip_to_number.existing_subnets[index(local.sorted_subnets, local.sorted_subnets[i+1])].start - 1
      }
    ],
    [{ 
      start = local.ip_to_number.existing_subnets[index(local.sorted_subnets, local.sorted_subnets[length(local.sorted_subnets) - 1])].end + 1,
      end = local.ip_to_number.vnet + pow(2, 32 - local.vnet_prefix_length) - 1
    }]
  )

  # Find the first gap that can accommodate the new subnet
  next_subnet_start = [
    for gap in local.subnet_gaps :
    gap.start if gap.end - gap.start + 1 >= local.new_subnet_size
  ][0]

  # Calculate the subnet index
  subnet_index = (local.next_subnet_start - local.ip_to_number.vnet) / local.new_subnet_size

  # Calculate the next available subnet
  next_subnet = cidrsubnet(
    var.vnet_cidr,
    var.new_subnet_prefix_length - local.vnet_prefix_length,
    floor(local.subnet_index)
  )

  # Generate IP addresses for the new subnet
  new_subnet_ip_list = var.new_subnet_prefix_length == 31 ? [
    cidrhost(local.next_subnet, 0),
    cidrhost(local.next_subnet, 1)
  ] : [
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