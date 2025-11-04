# Essential environment information for GitHub Actions and other modules
output "environments" {
  description = "Created environments with client IDs and subscription IDs"
  value = {
    for env_name, env in var.environments : env_name => {
      client_id       = azuread_application.landing_zones[local.env_to_sp_mapping[env_name]].client_id
      subscription_id = env.subscription_id
    }
  }
}

# GitHub environment names for workflow reference
output "github_environments" {
  description = "List of created GitHub environment names"
  value       = [for env in github_repository_environment.environments : env.environment]
}

# Key Vault name for secret storage reference
output "key_vault_name" {
  description = "Bootstrap Key Vault name"
  value       = var.bootstrap.github_enabled ? var.bootstrap.key_vault.name : null
}