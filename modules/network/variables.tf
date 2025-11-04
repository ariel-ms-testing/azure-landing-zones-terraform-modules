terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.100.0, < 6.0.0"
    }
  }
}

# ============================================================================
# INPUT VARIABLES - Simplified and Clean Schema  
# ============================================================================

variable "config" {
  description = "Network configuration with simplified schema"
  type = object({
    # Schema version for configuration validation
    schema_version = number
    
    # Global settings
    global = optional(object({
      naming_prefix       = optional(string, "")
      default_location    = optional(string, "westeurope")
      enable_diagnostics  = optional(bool, false)
      log_analytics_workspace_id = optional(string)
    }), {})

    # Hub networks (can be multiple for multi-region)
    hubs = optional(list(object({
      name               = string
      subscription_id    = optional(string)
      resource_group     = string
      location           = string
      
      # VNet configuration
      vnet = object({
        name          = string
        address_space = list(string)
        subnets = list(object({
          name             = string
          address_prefixes = list(string)
          # Optional: subnet-specific settings
          delegation       = optional(string)
          service_endpoints = optional(list(string), [])
        }))
      })
      
      # Optional: Firewall configuration
      firewall = optional(object({
        enabled           = optional(bool, true)
        name              = string
        sku_tier          = optional(string, "Standard") # Standard | Premium
        
        # Outbound connectivity method
        outbound_method   = optional(string, "firewall") # firewall | nat_gateway
        
        # NAT Gateway settings (when outbound_method = "nat_gateway")
        nat_gateway = optional(object({
          name                 = string
          public_ip_count      = optional(number, 1)
          idle_timeout_minutes = optional(number, 4)
          zones                = optional(list(string), ["1", "2", "3"])
        }))
        
        # Firewall policy settings
        policy = optional(object({
          name              = string
          threat_intel_mode = optional(string, "Alert") # Off | Alert | Deny
          private_ranges    = optional(list(string), ["IANAPrivateRanges"])
          
          # DNS proxy settings
          dns_proxy_enabled = optional(bool, true)
          dns_servers       = optional(list(string), [])
          
          # Rule collections (simplified)
          rules = optional(object({
            application_rules = optional(list(any), [])
            network_rules     = optional(list(any), [])
            nat_rules         = optional(list(any), [])
          }), {})
        }))
      }))
      
      # Optional: Additional features
      features = optional(object({
        enable_bastion    = optional(bool, false)
        enable_vpn        = optional(bool, false)
        enable_expressroute = optional(bool, false)
      }), {})
    })), [])

    # Spoke networks
    spokes = optional(list(object({
      name            = string
      subscription_id = optional(string)
      resource_group  = string
      location        = string
      
      # VNet configuration
      vnet = object({
        name          = string
        address_space = list(string)
        subnets = list(object({
          name             = string
          address_prefixes = list(string)
          delegation       = optional(string)
          service_endpoints = optional(list(string), [])
          
          # Routing configuration
          route_to_firewall = optional(bool, true)
        }))
      })
      
      # Connectivity settings
      connectivity = optional(object({
        hub_name              = string # Which hub to connect to
        enable_peering        = optional(bool, true)
        allow_forwarded_traffic = optional(bool, true)
        use_remote_gateways   = optional(bool, false)
      }))
    })), [])
  })

  # Validation rules
  validation {
    condition     = var.config.schema_version >= 2
    error_message = "Schema version must be 2 or higher for network-v2 module."
  }

  validation {
    condition = alltrue([
      for hub in var.config.hubs :
      contains([for subnet in hub.vnet.subnets : subnet.name], "AzureFirewallSubnet")
      if try(hub.firewall.enabled, true)
    ])
    error_message = "Hubs with firewall enabled must have an 'AzureFirewallSubnet' subnet."
  }

  validation {
    condition = alltrue([
      for spoke in var.config.spokes :
      spoke.connectivity == null || 
      length([for hub in var.config.hubs : hub if hub.name == spoke.connectivity.hub_name]) > 0
    ])
    error_message = "All spokes with connectivity defined must reference an existing hub name in connectivity.hub_name."
  }

  validation {
    condition = alltrue([
      for hub in var.config.hubs :
      contains(["firewall", "nat_gateway"], try(hub.firewall.outbound_method, "firewall"))
    ])
    error_message = "Firewall outbound_method must be either 'firewall' or 'nat_gateway'."
  }
}

variable "deployment_phase" {
  description = "Deployment type: hub (foundation+security) or spoke (foundation+connectivity)"
  type        = string
  default     = "hub"
  validation {
    condition     = contains(["hub", "spoke"], var.deployment_phase)
    error_message = "Deployment phase must be either 'hub' or 'spoke'."
  }
}

variable "deployment_type" {
  description = "DEPRECATED: Use deployment_phase instead. Deployment type: hub or spoke"
  type        = string
  default     = null
  validation {
    condition     = var.deployment_type == null || contains(["hub", "spoke"], coalesce(var.deployment_type, ""))
    error_message = "Deployment type must be either 'hub' or 'spoke'."
  }
}

variable "target_subscription_id" {
  description = "Target subscription ID for resource filtering (for multi-subscription deployments)"
  type        = string
  default     = null
}

variable "tf_backend_config" {
  description = "Configuration for remote state lookup (for cross-subscription communication)"
  type = object({
    resource_group   = string
    storage_account  = string
    container        = string
  })
  default = null
}

variable "tags" {
  description = "Default tags to apply to all resources"
  type        = map(string)
  default     = {}
}