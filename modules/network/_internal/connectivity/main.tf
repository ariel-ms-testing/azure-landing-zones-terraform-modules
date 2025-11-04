# ============================================================================
# Connectivity Component - Peering and Routing
# ============================================================================

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.100.0, < 6.0.0"
    }
  }
}

variable "peering_connections" {
  description = "VNet peering connections to create"
  type = list(object({
    name                      = string
    spoke_vnet_id            = string
    spoke_vnet_name          = string
    spoke_resource_group     = string
    hub_vnet_id              = string
    hub_vnet_name            = string
    hub_resource_group       = string
    allow_forwarded_traffic  = bool
    use_remote_gateways      = bool
  }))
  default = []
}

variable "route_tables" {
  description = "Route tables and routes to create"
  type = list(object({
    name                = string
    spoke_name          = string
    resource_group      = string
    location            = string
    firewall_ip         = string
    subnets_to_route    = list(object({
      name      = string
      subnet_id = string
    }))
  }))
  default = []
}

variable "remote_hub_references" {
  description = "Remote hub references for cross-subscription peering"
  type = map(object({
    vnet_id              = string
    vnet_name            = string
    resource_group_name  = string
    firewall_private_ip  = string
  }))
  default = {}
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Hub to Spoke peering
resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  for_each = { for peer in var.peering_connections : "${peer.name}-hub-to-spoke" => peer }
  
  name                      = "peer-hub-to-${each.value.spoke_vnet_name}"
  resource_group_name       = each.value.hub_resource_group
  virtual_network_name      = each.value.hub_vnet_name
  remote_virtual_network_id = each.value.spoke_vnet_id
  
  allow_virtual_network_access = true
  allow_forwarded_traffic      = each.value.allow_forwarded_traffic
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

# Spoke to Hub peering
resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  for_each = { for peer in var.peering_connections : "${peer.name}-spoke-to-hub" => peer }
  
  name                      = "peer-${each.value.spoke_vnet_name}-to-hub"
  resource_group_name       = each.value.spoke_resource_group
  virtual_network_name      = each.value.spoke_vnet_name
  remote_virtual_network_id = each.value.hub_vnet_id
  
  allow_virtual_network_access = true
  allow_forwarded_traffic      = each.value.allow_forwarded_traffic
  allow_gateway_transit        = false
  use_remote_gateways          = each.value.use_remote_gateways
}

# Route tables for spoke networks
resource "azurerm_route_table" "spoke" {
  for_each = { for rt in var.route_tables : rt.spoke_name => rt }
  
  name                = each.value.name
  location            = each.value.location
  resource_group_name = each.value.resource_group
  
  # Default route to firewall
  route {
    name                   = "default-to-firewall"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = each.value.firewall_ip
  }
  
  tags = merge(var.tags, {
    Purpose = "Spoke-to-Hub-Routing"
  })
}

# Associate route tables with subnets
resource "azurerm_subnet_route_table_association" "this" {
  for_each = merge([
    for rt in var.route_tables : {
      for subnet in rt.subnets_to_route :
      "${rt.spoke_name}-${subnet.name}" => {
        subnet_id      = subnet.subnet_id
        route_table_id = azurerm_route_table.spoke[rt.spoke_name].id
      }
    }
  ]...)
  
  subnet_id      = each.value.subnet_id
  route_table_id = each.value.route_table_id
}

# Cross-subscription peering using data sources
data "azurerm_virtual_network" "remote_hub" {
  for_each = var.remote_hub_references
  
  name                = each.value.vnet_name
  resource_group_name = each.value.resource_group_name
}

# Cross-subscription spoke to hub peering
resource "azurerm_virtual_network_peering" "cross_subscription_spoke_to_hub" {
  for_each = var.remote_hub_references
  
  name                      = "peer-spoke-to-${each.key}"
  resource_group_name       = "placeholder" # Will be set by calling module
  virtual_network_name      = "placeholder" # Will be set by calling module
  remote_virtual_network_id = data.azurerm_virtual_network.remote_hub[each.key].id
  
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
  
  lifecycle {
    ignore_changes = [
      resource_group_name,
      virtual_network_name
    ]
  }
}

# Outputs
output "peering_connections" {
  description = "Created VNet peering connections"
  value = {
    hub_to_spoke = {
      for name, peer in azurerm_virtual_network_peering.hub_to_spoke :
      name => {
        id   = peer.id
        name = peer.name
      }
    }
    spoke_to_hub = {
      for name, peer in azurerm_virtual_network_peering.spoke_to_hub :
      name => {
        id   = peer.id
        name = peer.name
      }
    }
  }
}

output "route_tables" {
  description = "Created route tables"
  value = {
    for name, rt in azurerm_route_table.spoke :
    name => {
      id   = rt.id
      name = rt.name
    }
  }
}