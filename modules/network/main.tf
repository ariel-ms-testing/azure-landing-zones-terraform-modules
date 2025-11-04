# ============================================================================
# Main Network Module - Orchestrates all components
# ============================================================================

# Local data processing and filtering
locals {
  # Extract global settings
  global_settings = var.config.global
  
  # Map deployment_phase to internal phases (support both deployment_phase and deployment_type for backwards compatibility)
  deployment_type = var.deployment_phase != null ? var.deployment_phase : var.deployment_type
  phases = local.deployment_type == "hub" ? {
    foundation   = true
    security     = true
    connectivity = true  # Enable connectivity for hub-to-spoke peering
  } : local.deployment_type == "spoke" ? {
    foundation   = true
    security     = false
    connectivity = true
  } : {
    foundation   = true
    security     = true
    connectivity = true
  }
  
  # Filter resources by subscription if specified
  all_hubs = var.config.hubs
  all_spokes = var.config.spokes
  
  # Apply subscription filtering
  filtered_hubs = var.target_subscription_id != null ? [
    for hub in local.all_hubs : hub
    if try(hub.subscription_id, "") == "" || hub.subscription_id == var.target_subscription_id
  ] : local.all_hubs
  
  filtered_spokes = var.target_subscription_id != null ? [
    for spoke in local.all_spokes : spoke
    if try(spoke.subscription_id, "") == "" || spoke.subscription_id == var.target_subscription_id
  ] : local.all_spokes
  
  # Combine all networks for VNet component
  all_networks = concat(
    [
      for hub in local.filtered_hubs : {
        name            = hub.name
        type            = "hub"
        subscription_id = hub.subscription_id
        resource_group  = hub.resource_group
        location        = hub.location
        vnet_name       = hub.vnet.name
        address_space   = hub.vnet.address_space
        subnets         = hub.vnet.subnets
      }
    ],
    [
      for spoke in local.filtered_spokes : {
        name            = spoke.name
        type            = "spoke"
        subscription_id = spoke.subscription_id
        resource_group  = spoke.resource_group
        location        = spoke.location
        vnet_name       = spoke.vnet.name
        address_space   = spoke.vnet.address_space
        subnets         = spoke.vnet.subnets
      }
    ]
  )
  
  # Prepare firewall configurations
  firewall_configs = local.phases.security ? [
    for hub in local.filtered_hubs : {
      name                = try(hub.firewall.name, "afw-${hub.name}")
      hub_name            = hub.name
      resource_group      = hub.resource_group
      location            = hub.location
      sku_tier            = try(hub.firewall.sku_tier, "Standard")
      outbound_method     = try(hub.firewall.outbound_method, "firewall")
      firewall_subnet_id  = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${hub.resource_group}/providers/Microsoft.Network/virtualNetworks/${hub.vnet.name}/subnets/AzureFirewallSubnet"
      
      # NAT Gateway configuration
      nat_gateway = try(hub.firewall.nat_gateway, {
        name                 = "natgw-${hub.name}"
        public_ip_count      = 1
        idle_timeout_minutes = 4
        zones                = ["1", "2", "3"]
      })
      
      # Policy configuration - handle the IANAPrivateRanges issue
      policy = merge(
        try(hub.firewall.policy, {}),
        {
          name = try(hub.firewall.policy.name, "afwp-${hub.name}")
          # Convert IANAPrivateRanges to actual private ranges for Azure Firewall Policy
          private_ranges = contains(try(hub.firewall.policy.private_ranges, []), "IANAPrivateRanges") ? ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"] : try(hub.firewall.policy.private_ranges, ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"])
        }
      )
    }
    if try(hub.firewall.enabled, true)
  ] : []
  
  # Prepare peering connections (only when both hub and spoke are in current deployment)
  peering_connections = local.phases.connectivity ? [
    for spoke in local.filtered_spokes : {
      name                     = spoke.name
      spoke_vnet_id           = "${spoke.resource_group}/providers/Microsoft.Network/virtualNetworks/${spoke.vnet.name}"
      spoke_vnet_name         = spoke.vnet.name
      spoke_resource_group    = spoke.resource_group
      hub_vnet_id             = "${[for h in local.filtered_hubs : h if h.name == spoke.connectivity.hub_name][0].resource_group}/providers/Microsoft.Network/virtualNetworks/${[for h in local.filtered_hubs : h if h.name == spoke.connectivity.hub_name][0].vnet.name}"
      hub_vnet_name           = [for h in local.filtered_hubs : h if h.name == spoke.connectivity.hub_name][0].vnet.name
      hub_resource_group      = [for h in local.filtered_hubs : h if h.name == spoke.connectivity.hub_name][0].resource_group
      allow_forwarded_traffic = spoke.connectivity.allow_forwarded_traffic
      use_remote_gateways     = spoke.connectivity.use_remote_gateways
    }
    if spoke.connectivity.enable_peering && 
       contains([for h in local.filtered_hubs : h.name], spoke.connectivity.hub_name)
  ] : []
  
  # Prepare route tables for spokes
  route_table_configs = local.phases.connectivity ? [
    for spoke in local.filtered_spokes : {
      name           = "rt-${spoke.name}"
      spoke_name     = spoke.name
      resource_group = spoke.resource_group
      location       = spoke.location
      firewall_ip    = try(
        data.terraform_remote_state.hubs[spoke.connectivity.hub_name].outputs.firewall_private_ips[spoke.connectivity.hub_name],
        "10.0.0.4"  # Default firewall IP in hub subnet range
      )
      subnets_to_route = [
        for subnet in spoke.vnet.subnets : {
          name      = subnet.name
          subnet_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${spoke.resource_group}/providers/Microsoft.Network/virtualNetworks/${spoke.vnet.name}/subnets/${subnet.name}"
        }
        if try(subnet.route_to_firewall, true)
      ]
    }
    # Create route tables for all spokes that have connectivity configuration
    # (both same-subscription and cross-subscription deployments)
    if spoke.connectivity != null &&
       length([for hub in var.config.hubs : hub if hub.name == spoke.connectivity.hub_name]) > 0
  ] : []
  
  # Disable tags for testing - causing deployment issues
  default_tags = {}
}

# Data source for current subscription context
data "azurerm_client_config" "current" {}

# ============================================================================
# Phase 1: Foundation (VNets and Subnets)
# ============================================================================

module "vnet" {
  count = local.phases.foundation ? 1 : 0
  
  source = "./_internal/vnet"
  
  networks      = local.all_networks
  naming_prefix = local.global_settings.naming_prefix
}

# ============================================================================
# Phase 2: Security (Firewalls and NAT Gateways)
# ============================================================================

module "firewall" {
  count = local.phases.security && length(local.firewall_configs) > 0 ? 1 : 0
  
  source = "./_internal/firewall"
  
  firewalls = local.firewall_configs
  
  depends_on = [module.vnet]
}

# ============================================================================
# Phase 3: Connectivity (Peering and Routing)
# ============================================================================

module "connectivity" {
  count = local.phases.connectivity ? 1 : 0
  
  source = "./_internal/connectivity"
  
  peering_connections = local.peering_connections
  route_tables       = local.route_table_configs
  
  depends_on = [module.vnet, module.firewall]
}

# ============================================================================
# Cross-subscription support
# ============================================================================

# Remote state data sources for hub information (when spokes are deployed separately)
data "terraform_remote_state" "hubs" {
  for_each = {
    for spoke in local.filtered_spokes : spoke.connectivity.hub_name => spoke.connectivity.hub_name
    if var.tf_backend_config != null &&
       !contains([for h in local.filtered_hubs : h.name], spoke.connectivity.hub_name)
  }
  
  backend = "azurerm"
  config = {
    resource_group_name  = var.tf_backend_config.resource_group
    storage_account_name = var.tf_backend_config.storage_account
    container_name       = var.tf_backend_config.container
    key                  = "${each.value}.tfstate"  # hub-westeurope.tfstate
  }
}

# Cross-subscription peering for spokes
resource "azurerm_virtual_network_peering" "cross_subscription_spoke_to_hub" {
  for_each = {
    for spoke in local.filtered_spokes : spoke.name => spoke
    if var.tf_backend_config != null &&
       !contains([for h in local.filtered_hubs : h.name], spoke.connectivity.hub_name) &&
       spoke.connectivity.enable_peering
  }
  
  name                      = "peer-${each.value.name}-to-${each.value.connectivity.hub_name}"
  resource_group_name       = each.value.resource_group
  virtual_network_name      = each.value.vnet.name
  remote_virtual_network_id = try(
    data.terraform_remote_state.hubs[each.value.connectivity.hub_name].outputs.virtual_networks[each.value.connectivity.hub_name].id,
    "/subscriptions/${[for hub in var.config.hubs : hub.subscription_id if hub.name == each.value.connectivity.hub_name][0]}/resourceGroups/${[for hub in var.config.hubs : hub.resource_group if hub.name == each.value.connectivity.hub_name][0]}/providers/Microsoft.Network/virtualNetworks/${[for hub in var.config.hubs : hub.vnet.name if hub.name == each.value.connectivity.hub_name][0]}"
  )
  
  allow_virtual_network_access = true
  allow_forwarded_traffic      = each.value.connectivity.allow_forwarded_traffic
  allow_gateway_transit        = false
  use_remote_gateways          = each.value.connectivity.use_remote_gateways
}

# Create hub-to-spoke peering using Azure CLI (cross-subscription)
resource "null_resource" "hub_to_spoke_peering" {
  for_each = {
    for spoke in local.filtered_spokes : spoke.name => spoke
    if var.tf_backend_config != null &&
       !contains([for h in local.filtered_hubs : h.name], spoke.connectivity.hub_name)
  }

  # Trigger recreation when peering configuration changes
  # Store all values needed for both create and destroy operations
  triggers = {
    spoke_vnet_id           = "/subscriptions/${each.value.subscription_id}/resourceGroups/${each.value.resource_group}/providers/Microsoft.Network/virtualNetworks/${each.value.vnet.name}"
    hub_vnet_id             = "/subscriptions/${[for hub in var.config.hubs : hub.subscription_id if hub.name == each.value.connectivity.hub_name][0]}/resourceGroups/${[for hub in var.config.hubs : hub.resource_group if hub.name == each.value.connectivity.hub_name][0]}/providers/Microsoft.Network/virtualNetworks/${[for hub in var.config.hubs : hub.vnet.name if hub.name == each.value.connectivity.hub_name][0]}"
    peering_name            = "peer-${each.value.connectivity.hub_name}-to-${each.value.name}"
    hub_resource_group      = [for hub in var.config.hubs : hub.resource_group if hub.name == each.value.connectivity.hub_name][0]
    hub_vnet_name           = [for hub in var.config.hubs : hub.vnet.name if hub.name == each.value.connectivity.hub_name][0]
    hub_subscription_id     = [for hub in var.config.hubs : hub.subscription_id if hub.name == each.value.connectivity.hub_name][0]
    allow_forwarded_traffic = each.value.connectivity.allow_forwarded_traffic
  }

  # Create hub-to-spoke peering using Azure CLI
  provisioner "local-exec" {
    command = <<-EOT
      az network vnet peering create \
        --resource-group "${self.triggers.hub_resource_group}" \
        --vnet-name "${self.triggers.hub_vnet_name}" \
        --name "${self.triggers.peering_name}" \
        --remote-vnet "${self.triggers.spoke_vnet_id}" \
        --allow-vnet-access true \
        --allow-forwarded-traffic ${self.triggers.allow_forwarded_traffic} \
        --allow-gateway-transit true \
        --subscription "${self.triggers.hub_subscription_id}"
    EOT
  }

  # Clean up peering when resource is destroyed
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      az network vnet peering delete \
        --resource-group "${self.triggers.hub_resource_group}" \
        --vnet-name "${self.triggers.hub_vnet_name}" \
        --name "${self.triggers.peering_name}" \
        --subscription "${self.triggers.hub_subscription_id}" || true
    EOT
  }

  # Ensure spoke VNet exists before creating peering
  depends_on = [module.vnet]
}

# ============================================================================
# Deployment logging and context
# ============================================================================

resource "null_resource" "deployment_context" {
  triggers = {
    deployment_phase    = local.deployment_type
    subscription_id     = data.azurerm_client_config.current.subscription_id
    hub_count          = length(local.filtered_hubs)
    spoke_count        = length(local.filtered_spokes)
    timestamp          = timestamp()
  }
  
  lifecycle {
    ignore_changes = [triggers["timestamp"]]
  }
  
  provisioner "local-exec" {
    command = "echo '[INFO] Network deployment - Phase: ${local.deployment_type}, Subscription: ${data.azurerm_client_config.current.subscription_id}, Hubs: ${length(local.filtered_hubs)}, Spokes: ${length(local.filtered_spokes)}'"
  }
}