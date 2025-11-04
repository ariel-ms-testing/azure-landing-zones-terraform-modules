# ============================================================================
# Firewall and Security Component
# ============================================================================

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.100.0, < 6.0.0"
    }
  }
}

variable "firewalls" {
  description = "Firewall configurations"
  type = list(object({
    name              = string
    hub_name          = string
    resource_group    = string
    location          = string
    sku_tier          = string
    outbound_method   = string # "firewall" or "nat_gateway"
    
    # Firewall subnet information
    firewall_subnet_id = string
    
    # NAT Gateway configuration
    nat_gateway = optional(object({
      name                 = string
      public_ip_count      = number
      idle_timeout_minutes = number
      zones                = list(string)
    }))
    
    # Policy configuration
    policy = object({
      name              = string
      threat_intel_mode = string
      private_ranges    = list(string)
      dns_proxy_enabled = bool
      dns_servers       = list(string)
      rules = object({
        application_rules = list(any)
        network_rules     = list(any)
        nat_rules         = list(any)
      })
    })
  }))
  default = []
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Create firewall policies using AVM
module "firewall_policy" {
  source = "Azure/avm-res-network-firewallpolicy/azurerm"
  
  for_each = { for fw in var.firewalls : fw.hub_name => fw }
  
  name                = each.value.policy.name
  location            = each.value.location
  resource_group_name = each.value.resource_group
  
  # Disable telemetry for testing
  enable_telemetry = false
  
  # DNS configuration
  firewall_policy_dns = each.value.policy.dns_proxy_enabled ? {
    proxy_enabled = true
    servers       = length(each.value.policy.dns_servers) > 0 ? each.value.policy.dns_servers : null
  } : null
  
  # Threat intelligence
  firewall_policy_threat_intelligence_mode = each.value.policy.threat_intel_mode
  
  # Private ranges for SNAT
  firewall_policy_private_ip_ranges = each.value.policy.private_ranges
  
  tags = var.tags
}

# Create rule collection groups
module "rule_collection_groups" {
  source = "Azure/avm-res-network-firewallpolicy/azurerm//modules/rule_collection_groups"
  
  for_each = { for fw in var.firewalls : fw.hub_name => fw }
  
  firewall_policy_rule_collection_group_firewall_policy_id = module.firewall_policy[each.key].resource.id
  firewall_policy_rule_collection_group_name               = "DefaultRuleCollectionGroup"
  firewall_policy_rule_collection_group_priority           = 100
  
  # Rule collections
  firewall_policy_rule_collection_group_application_rule_collection = each.value.policy.rules.application_rules
  firewall_policy_rule_collection_group_network_rule_collection     = each.value.policy.rules.network_rules
  firewall_policy_rule_collection_group_nat_rule_collection         = each.value.policy.rules.nat_rules
}

# NAT Gateway for enhanced outbound connectivity
module "nat_gateway" {
  source = "Azure/avm-res-network-natgateway/azurerm"
  
  for_each = { 
    for fw in var.firewalls : fw.hub_name => fw 
    if fw.outbound_method == "nat_gateway" 
  }
  
  name                = each.value.nat_gateway.name
  location            = each.value.location
  resource_group_name = each.value.resource_group
  
  # Disable telemetry for testing
  enable_telemetry = false
  
  # Basic NAT Gateway settings
  idle_timeout_in_minutes = each.value.nat_gateway.idle_timeout_minutes
  zones                   = each.value.nat_gateway.zones
  
  tags = var.tags
}

# Public IPs for NAT Gateway
resource "azurerm_public_ip" "nat_gateway" {
  for_each = merge([
    for fw in var.firewalls : {
      for i in range(fw.nat_gateway.public_ip_count) :
      "${fw.hub_name}-nat-pip-${i + 1}" => {
        name            = "${fw.nat_gateway.name}-pip-${i + 1}"
        location        = fw.location
        resource_group  = fw.resource_group
        hub_name        = fw.hub_name
      }
    }
    if fw.outbound_method == "nat_gateway"
  ]...)
  
  name                = each.value.name
  location            = each.value.location
  resource_group_name = each.value.resource_group
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
  
  tags = var.tags
}

# Associate NAT Gateway with subnet
resource "azurerm_subnet_nat_gateway_association" "this" {
  for_each = { 
    for fw in var.firewalls : fw.hub_name => fw 
    if fw.outbound_method == "nat_gateway" 
  }
  
  subnet_id      = each.value.firewall_subnet_id
  nat_gateway_id = module.nat_gateway[each.key].resource_id
}

# Associate Public IPs with NAT Gateway
resource "azurerm_nat_gateway_public_ip_association" "this" {
  for_each = azurerm_public_ip.nat_gateway
  
  nat_gateway_id       = module.nat_gateway[regex("^(.+)-nat-pip-\\d+$", each.key)[0]].resource_id
  public_ip_address_id = each.value.id
}

# Public IPs for firewall (when using firewall outbound method)
resource "azurerm_public_ip" "firewall" {
  for_each = { 
    for fw in var.firewalls : fw.hub_name => fw 
    if fw.outbound_method == "firewall" 
  }
  
  name                = "${each.value.name}-pip"
  location            = each.value.location
  resource_group_name = each.value.resource_group
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
  
  tags = var.tags
}

# Management Public IP for NAT Gateway method
resource "azurerm_public_ip" "firewall_mgmt" {
  for_each = { 
    for fw in var.firewalls : fw.hub_name => fw 
    if fw.outbound_method == "nat_gateway" 
  }
  
  name                = "${each.value.name}-mgmt-pip"
  location            = each.value.location
  resource_group_name = each.value.resource_group
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
  
  tags = var.tags
}

# Azure Firewall using AVM
module "azure_firewall" {
  source = "Azure/avm-res-network-azurefirewall/azurerm"
  
  for_each = { for fw in var.firewalls : fw.hub_name => fw }
  
  name                = each.value.name
  location            = each.value.location
  resource_group_name = each.value.resource_group
  
  # Disable telemetry for testing
  enable_telemetry = false
  
  firewall_sku_name = "AZFW_VNet"
  firewall_sku_tier = each.value.sku_tier
  
  firewall_policy_id = module.firewall_policy[each.key].resource.id
  
  # IP configuration
  ip_configurations = {
    default = {
      name                 = "default"
      subnet_id            = each.value.firewall_subnet_id
      public_ip_address_id = each.value.outbound_method == "firewall" ? azurerm_public_ip.firewall[each.key].id : azurerm_public_ip.firewall_mgmt[each.key].id
    }
  }
  
  tags = var.tags
  
  depends_on = [
    module.firewall_policy,
    module.rule_collection_groups
  ]
}

# Outputs
output "firewalls" {
  description = "Created Azure Firewalls"
  value = {
    for name, fw in module.azure_firewall :
    name => {
      id                     = fw.resource.id
      name                   = fw.resource.name
      private_ip_address     = fw.resource.ip_configuration[0].private_ip_address
      public_ip_addresses    = [for ip_config in fw.resource.ip_configuration : ip_config.public_ip_address_id]
      resource_group_name    = fw.resource.resource_group_name
      location              = fw.resource.location
    }
  }
}

output "nat_gateways" {
  description = "Created NAT Gateways"
  value = {
    for name, nat in module.nat_gateway :
    name => {
      id                  = nat.resource_id
      name                = nat.resource.name
      public_ip_addresses = [for pip_key, pip in nat.public_ip_resource : pip.ip_address]
      resource_group_name = nat.resource.resource_group_name
      location           = nat.resource.location
    }
  }
}

output "firewall_policies" {
  description = "Created firewall policies"
  value = {
    for name, policy in module.firewall_policy :
    name => {
      id   = policy.resource.id
      name = policy.resource.name
    }
  }
}

output "firewall_private_ips" {
  description = "Firewall private IP addresses for routing"
  value = {
    for name, fw in module.azure_firewall :
    name => fw.resource.ip_configuration[0].private_ip_address
  }
}