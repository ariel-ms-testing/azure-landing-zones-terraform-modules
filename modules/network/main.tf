# ============================================================================
# Main Network Module - Orchestrates all components
# ============================================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.100.0, < 6.0.0"
    }
  }
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