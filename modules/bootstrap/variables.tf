variable "github" {
  description = "GitHub repository configuration"
  type = object({
    owner = string
    repo  = string
  })
}

variable "bootstrap" {
  description = "Bootstrap deployment configuration"
  type = object({
    # GitHub Actions deployment
    github_enabled = bool  # Enable GitHub Actions deployment
    
    # GitHub configuration (only used if github_enabled = true)
    github = optional(object({
      use_single_sp             = bool  # true = one SP for all environments, false = one SP per module type
      use_module_scoped_sp      = optional(bool, false)  # true = one SP per module type
      use_federated_credentials = bool  # true = OIDC, false = client secrets
    }))
    
    # Key Vault configuration for storing secrets
    key_vault = object({
      name               = string                     # Key Vault name
      allowed_ips        = optional(list(string), [])
      allowed_subnets    = optional(list(string), [])
      purge_protection   = optional(bool, false)
    })
  })
  
  validation {
    condition = !var.bootstrap.github_enabled || var.bootstrap.github != null
    error_message = "GitHub configuration is required when github_enabled is true."
  }
  
  validation {
    condition = !var.bootstrap.github_enabled || var.bootstrap.github == null || var.bootstrap.github.use_single_sp || var.bootstrap.github.use_module_scoped_sp
    error_message = "Either use_single_sp or use_module_scoped_sp must be true when GitHub is enabled."
  }
}

variable "environments" {
  description = "Environment configurations with their module types and permissions"
  type = map(object({
    module                = string  # "network", "mg", "policy"
    subscription_id       = string
    scope_id             = optional(string)        # For MG and Policy modules
    managed_subscriptions = optional(list(string)) # For MG module only
    enable_pull_requests = optional(bool, false)
    protection_rules = optional(object({
      wait_timer              = optional(number)
      prevent_self_review     = optional(bool)
      required_reviewer_count = optional(number)
    }))
  }))
  
  validation {
    condition = alltrue([
      for env_name, env in var.environments :
      contains(["network", "mg", "policy"], env.module)
    ])
    error_message = "Environment module must be one of: network, mg, policy."
  }
  
  validation {
    condition = alltrue([
      for env_name, env in var.environments :
      env.module != "mg" || (env.scope_id != null && env.scope_id != "")
    ])
    error_message = "Management Groups environments must specify scope_id."
  }
  
  validation {
    condition = alltrue([
      for env_name, env in var.environments :
      env.module != "policy" || (env.scope_id != null && env.scope_id != "")
    ])
    error_message = "Policy environments must specify scope_id."
  }
}

variable "tfstate" {
  description = "External Terraform state storage configuration (created by create-tfstate-storage.sh script)"
  type = object({
    subscription_id = string
    resource_group  = string
    location        = string
    storage_account = string
    container       = string
  })
  
  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.tfstate.storage_account))
    error_message = "Storage account name must be 3-24 characters, lowercase letters and numbers only."
  }
}

variable "tenant_id" {
  description = "Azure AD tenant ID"
  type        = string
  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.tenant_id))
    error_message = "Tenant ID must be a valid GUID."
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}