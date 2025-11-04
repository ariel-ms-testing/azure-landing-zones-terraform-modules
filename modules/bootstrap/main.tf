terraform {
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
}

# Data sources for current context
data "azuread_client_config" "current" {}

# Data source for external storage account (created by script)
data "azurerm_storage_account" "tfstate" {
  name                = var.tfstate.storage_account
  resource_group_name = var.tfstate.resource_group
}

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

# Create Azure AD Application for each environment (or single shared one)
resource "azuread_application" "landing_zones" {
  for_each     = local.sp_environments
  display_name = var.bootstrap.github.use_module_scoped_sp ? "tf-${each.key}" : "tf-shared-sp"
  
  web {
    redirect_uris = ["https://github.com/${var.github.owner}/${var.github.repo}"]
  }

  lifecycle {
    ignore_changes = [
      web[0].redirect_uris
    ]
  }
}

# Create Service Principals for each application
resource "azuread_service_principal" "landing_zones" {
  for_each  = azuread_application.landing_zones
  client_id = each.value.client_id
}

# Create client secrets (only if not using federated credentials)
resource "azuread_application_password" "landing_zones" {
  for_each          = local.create_client_secrets ? azuread_application.landing_zones : {}
  application_id    = each.value.object_id
  display_name      = "terraform-secret-${each.key}"
  
  # Expire in 12 months
  end_date = timeadd(timestamp(), "8760h")
  
  lifecycle {
    ignore_changes = [
      end_date
    ]
  }
}

# Create OIDC federated identity credentials for GitHub Actions (one per environment, even with single SP)
resource "azuread_application_federated_identity_credential" "github_actions" {
  for_each       = local.create_oidc_credentials ? var.environments : {}
  application_id = azuread_application.landing_zones[local.env_to_sp_mapping[each.key]].id
  display_name   = "github-actions-${each.key}"
  description    = "Federated credential for GitHub Actions in ${each.key} environment"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github.owner}/${var.github.repo}:environment:${each.key}"
}

# Create OIDC federated identity credentials for pull requests (if enabled)
resource "azuread_application_federated_identity_credential" "github_pull_requests" {
  for_each       = local.create_oidc_credentials ? { for k, v in var.environments : k => v if v.enable_pull_requests } : {}
  application_id = azuread_application.landing_zones[local.env_to_sp_mapping[each.key]].id
  display_name   = "github-pr-${each.key}"
  description    = "Federated credential for GitHub pull requests in ${each.key} environment"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github.owner}/${var.github.repo}:pull_request"
}

# Role assignments for Terraform state storage
resource "azurerm_role_assignment" "tfstate_blob_contributor" {
  for_each = local.create_service_principals ? local.sp_environments : {}
  
  scope                = "/subscriptions/${var.tfstate.subscription_id}/resourceGroups/${var.tfstate.resource_group}/providers/Microsoft.Storage/storageAccounts/${var.tfstate.storage_account}/blobServices/default/containers/${var.tfstate.container}"
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azuread_service_principal.landing_zones[each.key].object_id
}

# Role assignments for Network environments
resource "azurerm_role_assignment" "network_contributor" {
  for_each = local.create_service_principals && length([for k, v in var.environments : k if v.module == "network"]) > 0 ? {
    # One assignment per unique subscription for network environments
    for sub_id in distinct([for k, v in var.environments : v.subscription_id if v.module == "network"]) : 
    "network-${sub_id}" => {
      subscription_id = sub_id
      principal_id = var.bootstrap.github.use_module_scoped_sp ? azuread_service_principal.landing_zones["network-shared"].object_id : azuread_service_principal.landing_zones["shared"].object_id
    }
  } : {}
  
  scope                = "/subscriptions/${each.value.subscription_id}"
  role_definition_name = var.bootstrap.github.use_module_scoped_sp ? "Contributor" : "Network Contributor"
  principal_id         = each.value.principal_id
}

# Role assignments for Management Groups environments
resource "azurerm_role_assignment" "mg_contributor" {
  for_each = local.create_service_principals && length([for k, v in var.environments : k if v.module == "mg"]) > 0 ? {
    # One assignment per unique scope_id for MG environments
    for scope_id in distinct([for k, v in var.environments : v.scope_id if v.module == "mg" && v.scope_id != null]) :
    "mg-${replace(scope_id, "/", "-")}" => {
      scope_id = scope_id
      principal_id = var.bootstrap.github.use_module_scoped_sp ? azuread_service_principal.landing_zones["mg-shared"].object_id : azuread_service_principal.landing_zones["shared"].object_id
    }
  } : {}
  
  scope                = each.value.scope_id
  role_definition_name = "Management Group Contributor"
  principal_id         = each.value.principal_id
}

# Role assignments for Management Groups to manage subscriptions
resource "azurerm_role_assignment" "mg_subscription_owner" {
  for_each = local.create_service_principals && length(flatten([for k, v in var.environments : v.managed_subscriptions if v.module == "mg" && v.managed_subscriptions != null])) > 0 ? {
    # One assignment per unique subscription for MG environments
    for sub_id in distinct(flatten([for k, v in var.environments : v.managed_subscriptions if v.module == "mg" && v.managed_subscriptions != null])) :
    "mg-owner-${sub_id}" => {
      sub_id = sub_id
      principal_id = var.bootstrap.github.use_module_scoped_sp ? azuread_service_principal.landing_zones["mg-shared"].object_id : azuread_service_principal.landing_zones["shared"].object_id
    }
  } : {}
  
  scope                = "/subscriptions/${each.value.sub_id}"
  role_definition_name = "Owner"
  principal_id         = each.value.principal_id
}

# Role assignments for Policy environments
resource "azurerm_role_assignment" "policy_contributor" {
  for_each = local.create_service_principals && length([for k, v in var.environments : k if v.module == "policy"]) > 0 ? {
    # One assignment per unique scope_id for Policy environments
    for scope_id in distinct([for k, v in var.environments : v.scope_id if v.module == "policy" && v.scope_id != null]) :
    "policy-${replace(scope_id, "/", "-")}" => {
      scope_id = scope_id
      principal_id = var.bootstrap.github.use_module_scoped_sp ? azuread_service_principal.landing_zones["policy-shared"].object_id : azuread_service_principal.landing_zones["shared"].object_id
    }
  } : {}
  
  scope                = each.value.scope_id
  role_definition_name = "Resource Policy Contributor"
  principal_id         = each.value.principal_id
}

# Create GitHub environments (always when GitHub enabled - maintains matrix workflow compatibility)
resource "github_repository_environment" "environments" {
  for_each    = local.create_github_environments ? var.environments : {}
  repository  = var.github.repo
  environment = each.key
}

# Set GitHub environment secrets - CLIENT_ID (sensitive)
resource "github_actions_environment_secret" "client_id" {
  for_each      = local.set_github_variables ? var.environments : {}
  repository    = var.github.repo
  environment   = github_repository_environment.environments[each.key].environment
  secret_name   = "AZURE_CLIENT_ID"
  plaintext_value = azuread_application.landing_zones[local.env_to_sp_mapping[each.key]].client_id
}

# Set GitHub environment secrets - TENANT_ID (sensitive)
resource "github_actions_environment_secret" "tenant_id" {
  for_each      = local.set_github_variables ? var.environments : {}
  repository    = var.github.repo
  environment   = github_repository_environment.environments[each.key].environment
  secret_name   = "AZURE_TENANT_ID"
  plaintext_value = var.tenant_id
}

# Set GitHub environment secrets - SUBSCRIPTION_ID (for all environments, sensitive)
resource "github_actions_environment_secret" "subscription_id" {
  for_each      = local.set_github_variables ? var.environments : {}
  repository    = var.github.repo
  environment   = github_repository_environment.environments[each.key].environment
  secret_name   = "AZURE_SUBSCRIPTION_ID"
  plaintext_value = each.value.subscription_id
}

# Set GitHub environment secrets - CLIENT_SECRET (only if not using federated credentials)
resource "github_actions_environment_secret" "client_secret" {
  for_each        = local.set_github_variables && !var.bootstrap.github.use_federated_credentials ? var.environments : {}
  repository      = var.github.repo
  environment     = github_repository_environment.environments[each.key].environment
  secret_name     = "AZURE_CLIENT_SECRET"
  plaintext_value = azuread_application_password.landing_zones[local.env_to_sp_mapping[each.key]].value
}

# Set GitHub environment secrets - Terraform Backend Configuration (sensitive)
resource "github_actions_environment_secret" "tf_backend_resource_group" {
  for_each      = local.set_github_variables ? var.environments : {}
  repository    = var.github.repo
  environment   = github_repository_environment.environments[each.key].environment
  secret_name   = "TF_BACKEND_RESOURCE_GROUP"
  plaintext_value = var.tfstate.resource_group
}

resource "github_actions_environment_secret" "tf_backend_storage_account" {
  for_each      = local.set_github_variables ? var.environments : {}
  repository    = var.github.repo
  environment   = github_repository_environment.environments[each.key].environment
  secret_name   = "TF_BACKEND_STORAGE_ACCOUNT"
  plaintext_value = var.tfstate.storage_account
}

resource "github_actions_environment_secret" "tf_backend_container" {
  for_each      = local.set_github_variables ? var.environments : {}
  repository    = var.github.repo
  environment   = github_repository_environment.environments[each.key].environment
  secret_name   = "TF_BACKEND_CONTAINER"
  plaintext_value = var.tfstate.container
}

resource "github_actions_environment_secret" "tf_backend_key" {
  for_each      = local.set_github_variables ? var.environments : {}
  repository    = var.github.repo
  environment   = github_repository_environment.environments[each.key].environment
  secret_name   = "TF_BACKEND_KEY"
  plaintext_value = "${each.key}.tfstate"
}