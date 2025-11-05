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