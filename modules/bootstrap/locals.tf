# Local values for determining what to create based on configuration
locals {
  # Always create service principals when GitHub is enabled (no local dev for now)
  create_service_principals = var.bootstrap.github_enabled
  
  # If GitHub enabled: always create ALL environments (maintains matrix workflow compatibility)
  create_github_environments = var.bootstrap.github_enabled
  
  # If GitHub enabled: always set environment variables and secrets
  set_github_variables = var.bootstrap.github_enabled
  
  # Create OIDC federated credentials (only if GitHub enabled and federated creds chosen)
  create_oidc_credentials = (
    var.bootstrap.github_enabled && 
    var.bootstrap.github.use_federated_credentials
  )
  
  # Create client secrets (only if GitHub enabled and NOT using federated creds)
  create_client_secrets = (
    var.bootstrap.github_enabled && 
    !var.bootstrap.github.use_federated_credentials
  )
  
  # Map environments to their module's SP for GitHub secrets
  env_to_sp_mapping = var.bootstrap.github.use_module_scoped_sp ? {
    for env_name, env in var.environments : env_name => "${env.module}-shared"
  } : {
    for env_name, env in var.environments : env_name => "shared"
  }
  
  # List of enabled modules
  enabled_modules = distinct([for k, v in var.environments : v.module])

  # Determine which environments to create SPs for
  sp_environments = var.bootstrap.github_enabled ? (
    var.bootstrap.github.use_module_scoped_sp ? {
      # Create one SP per enabled module type
      for module_name in local.enabled_modules : "${module_name}-shared" => {
        module                = module_name
        subscription_id       = var.tfstate.subscription_id
        scope_id             = contains(["mg", "policy"], module_name) ? try([for k, v in var.environments : v.scope_id if v.module == module_name][0], null) : null
        managed_subscriptions = (
          module_name == "mg" ? flatten([for k, v in var.environments : v.managed_subscriptions if v.module == "mg" && v.managed_subscriptions != null]) :
          module_name == "network" ? distinct([for k, v in var.environments : v.subscription_id if v.module == "network"]) : []
        )
        enable_pull_requests = false
        protection_rules     = null
        environments         = [for k, v in var.environments : k if v.module == module_name]
      }
    } : {
      "shared" = {
        module                = "shared"
        subscription_id       = var.tfstate.subscription_id
        scope_id             = null
        managed_subscriptions = flatten([for env_name, env in var.environments : env.managed_subscriptions if env.managed_subscriptions != null])
        enable_pull_requests = false
        protection_rules     = null
        environments         = keys(var.environments)
      }
    }
  ) : {}
}