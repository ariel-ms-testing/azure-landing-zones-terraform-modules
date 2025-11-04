# ============================================================================
# VNet and Subnet Management Component
# ============================================================================

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.100.0, < 6.0.0"
    }
  }
}

# Input variables for the VNet component
variable "networks" {
  description = "List of networks (hubs and spokes) to create"
  type = list(object({
    name               = string
    type               = string # "hub" or "spoke"
    subscription_id    = optional(string)
    resource_group     = string
    location           = string
    vnet_name          = string
    address_space      = list(string)
    subnets = list(object({
      name             = string
      address_prefixes = list(string)
      delegation       = optional(string)
      service_endpoints = optional(list(string), [])
    }))
  }))
}

variable "naming_prefix" {
  description = "Naming prefix for resources"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Data source for current subscription
data "azurerm_client_config" "current" {}

# Create resource groups
resource "azurerm_resource_group" "this" {
  for_each = { for net in var.networks : net.name => net }
  
  name     = each.value.resource_group
  location = each.value.location
  tags     = var.tags
}

# Create virtual networks
resource "azurerm_virtual_network" "this" {
  for_each = { for net in var.networks : net.name => net }
  
  name                = each.value.vnet_name
  location            = azurerm_resource_group.this[each.key].location
  resource_group_name = azurerm_resource_group.this[each.key].name
  address_space       = each.value.address_space
  
  tags = merge(var.tags, {
    NetworkType = each.value.type
  })
}

# Flatten subnets for easier management
locals {
  # Create a flat map of all subnets with network context
  all_subnets = merge([
    for net_name, net in { for n in var.networks : n.name => n } : {
      for subnet in net.subnets :
      "${net_name}|${subnet.name}" => {
        network_name      = net_name
        network_type      = net.type
        subnet_name       = subnet.name
        address_prefixes  = subnet.address_prefixes
        delegation        = subnet.delegation
        service_endpoints = subnet.service_endpoints
        vnet_name         = azurerm_virtual_network.this[net_name].name
        resource_group    = azurerm_resource_group.this[net_name].name
      }
    }
  ]...)
}

# Create subnets
resource "azurerm_subnet" "this" {
  for_each = local.all_subnets
  
  name                 = each.value.subnet_name
  resource_group_name  = each.value.resource_group
  virtual_network_name = each.value.vnet_name
  address_prefixes     = each.value.address_prefixes
  service_endpoints    = each.value.service_endpoints
  
  # Optional subnet delegation
  dynamic "delegation" {
    for_each = each.value.delegation != null ? [1] : []
    content {
      name = "delegation"
      service_delegation {
        name    = each.value.delegation
        actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
      }
    }
  }
}

# Outputs
output "resource_groups" {
  description = "Created resource groups"
  value = {
    for name, rg in azurerm_resource_group.this :
    name => {
      id       = rg.id
      name     = rg.name
      location = rg.location
    }
  }
}

output "virtual_networks" {
  description = "Created virtual networks"
  value = {
    for name, vnet in azurerm_virtual_network.this :
    name => {
      id                = vnet.id
      name              = vnet.name
      resource_group    = vnet.resource_group_name
      location          = vnet.location
      address_space     = vnet.address_space
      subnet_ids        = [
        for subnet_key, subnet in azurerm_subnet.this :
        subnet.id
        if startswith(subnet_key, "${name}|")
      ]
    }
  }
}

output "subnets" {
  description = "Created subnets organized by network"
  value = {
    for name, net in { for n in var.networks : n.name => n } :
    name => {
      for subnet_key, subnet in azurerm_subnet.this :
      subnet.name => {
        id               = subnet.id
        name             = subnet.name
        address_prefixes = subnet.address_prefixes
        vnet_id          = azurerm_virtual_network.this[name].id
      }
      if startswith(subnet_key, "${name}|")
    }
  }
}

# Special output for Azure Firewall subnets (used by firewall component)
output "firewall_subnet_ids" {
  description = "Azure Firewall subnet IDs by network name"
  value = {
    for subnet_key, subnet in azurerm_subnet.this :
    split("|", subnet_key)[0] => subnet.id
    if endswith(subnet_key, "|AzureFirewallSubnet")
  }
}