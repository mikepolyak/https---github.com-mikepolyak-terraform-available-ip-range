module "subnet_calculator" {
  source                  = "./vnet_subnet_module"
  vnet_cidr               = "10.0.0.0/16"
  existing_subnets_cidr   = ["10.0.0.0/27", "10.0.0.32/27"]
  new_subnet_prefix_length = 27
}

output "next_subnet" {
  value = module.subnet_calculator.next_available_subnet
}

output "new_ip_addresses" {
  value = module.subnet_calculator.new_subnet_ip_addresses
}

output "new_ip_count" {
  value = module.subnet_calculator.new_subnet_ip_count
}