terraform {
  required_version = ">= 1.5"
  
  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    github = {
      source  = "integrations/github"
      version = "~> 5.0"
    }
  }
  
  # Backend configuration will be provided via backend.hcl file
  backend "azurerm" {}
}

# Configure providers
provider "azuread" {
  tenant_id = var.tenant_id != null ? var.tenant_id : local.bootstrap_config.tenant_id
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
  subscription_id = var.tfstate_subscription_id != null ? var.tfstate_subscription_id : local.tfstate_config.subscription_id
  use_cli = true
}

provider "github" {
  owner = var.github_owner != null ? var.github_owner : local.github_config.owner
}

# Parse bootstrap configuration
locals {
  # Parse the bootstrap YAML configuration
  bootstrap_config = yamldecode(file("../../configs/bootstrap.yaml"))
  
  # Extract GitHub configuration
  github_config = local.bootstrap_config.github
  
  # Extract tfstate configuration
  tfstate_config = local.bootstrap_config.tfstate
  
  # Build environments from bootstrap config
  environments = merge(
    # Network environments (hubs and spokes)
    local.bootstrap_config.modules.network.enabled ? merge(
      # Hub environments
      {
        for hub in local.bootstrap_config.hubs : hub.name => {
          module          = "network"
          subscription_id = hub.subscription_id
          scope_id        = null
          managed_subscriptions = null
          enable_pull_requests = false
        }
      },
      # Spoke environments  
      {
        for spoke in try(local.bootstrap_config.spokes, []) : spoke.name => {
          module          = "network"
          subscription_id = spoke.subscription_id
          scope_id        = null
          managed_subscriptions = null
          enable_pull_requests = false
        }
      }
    ) : {},
    
    # Management Groups environment
    local.bootstrap_config.modules.mg.enabled ? {
      "${local.bootstrap_config.modules.mg.environment}" = {
        module                = "mg"
        subscription_id       = try(local.bootstrap_config.modules.mg.subscription_id, local.tfstate_config.subscription_id)
        scope_id             = local.bootstrap_config.modules.mg.scope_id
        managed_subscriptions = try(local.bootstrap_config.modules.mg.managed_subscriptions, [])
        enable_pull_requests = false
      }
    } : {},
    
    # Policy environment
    local.bootstrap_config.modules.policy.enabled ? {
      "${local.bootstrap_config.modules.policy.environment}" = {
        module          = "policy"
        subscription_id = try(local.bootstrap_config.modules.policy.subscription_id, local.tfstate_config.subscription_id)
        scope_id        = local.bootstrap_config.modules.policy.scope_id
        managed_subscriptions = null
        enable_pull_requests = false
      }
    } : {}
  )
}

# Call the bootstrap module
module "bootstrap" {
  source = "../../modules/bootstrap"
  
  tenant_id = local.bootstrap_config.tenant_id
  
  github = {
    owner = local.github_config.owner
    repo  = local.github_config.repo
  }
  
  bootstrap = local.bootstrap_config.bootstrap
  
  environments = local.environments
  
  tfstate = {
    subscription_id = local.tfstate_config.subscription_id
    resource_group  = local.tfstate_config.resource_group
    location        = local.tfstate_config.location
    storage_account = local.tfstate_config.storage_account
    container       = local.tfstate_config.container
  }
}