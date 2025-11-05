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