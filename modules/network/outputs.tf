# ============================================================================
# Network Module Outputs - Inter-Module Communication
# ============================================================================

# Foundation infrastructure references
output "virtual_networks" {
  description = "VNet information for external module reference"
  value = try(module.vnet[0].virtual_networks, {})
}

output "subnets" {
  description = "Subnet information for workload deployment"
  value = try(module.vnet[0].subnets, {})
}

# Security component references
output "firewall_private_ips" {
  description = "Firewall private IP addresses for routing configuration"
  value = try(module.firewall[0].firewall_private_ips, {})
}

output "security_components" {
  description = "Security component references for external modules"
  value = {
    firewalls     = try(module.firewall[0].firewalls, {})
    nat_gateways  = try(module.firewall[0].nat_gateways, {})
  }
}

# Deployment status for dependency management
output "deployment_info" {
  description = "Deployment status information"
  value = {
    deployment_phase    = var.deployment_phase
    target_subscription = var.target_subscription_id
    components_deployed = {
      foundation   = contains(["all", "foundation"], var.deployment_phase)
      security     = contains(["all", "security"], var.deployment_phase)
      connectivity = contains(["all", "connectivity"], var.deployment_phase)
    }
  }
}

