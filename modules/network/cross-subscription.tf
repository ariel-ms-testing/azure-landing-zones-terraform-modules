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