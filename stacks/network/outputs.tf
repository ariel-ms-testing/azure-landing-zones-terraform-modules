# ============================================================================
# Network V2 Stack Outputs - Inter-Module Communication Only
# ============================================================================

# Essential network references for external module consumption
output "networks" {
  description = "Network references for external modules (VNet IDs, subnets, connectivity)"
  value = {
    virtual_networks = module.network.virtual_networks
    subnets         = module.network.subnets
    firewall_ips    = module.network.firewall_private_ips
  }
}

# Deployment phase information for dependent modules
output "deployment_status" {
  description = "Deployment status for dependency management"
  value = {
    phase_completed = module.network.deployment_info.deployment_phase
    components_ready = module.network.deployment_info.components_deployed
  }
}