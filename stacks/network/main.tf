terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.100.0, < 6.0.0"
    }
  }
  
  # Backend configuration
  # Initialize with: terraform init -backend-config=backend.hcl
  backend "azurerm" {}
}

provider "azurerm" {
  features {}
}

# ============================================================================
# Configuration and Variables
# ============================================================================

variable "config_file" {
  description = "Path to the network YAML configuration file"
  type        = string
  default     = "../../configs/network.yaml"
}

variable "environment_name" {
  description = "Name of the environment being deployed"
  type        = string
  default     = ""
}

variable "deployment_type" {
  description = "Type of deployment: hub or spoke"
  type        = string
  default     = "hub"
  
  validation {
    condition     = contains(["hub", "spoke"], var.deployment_type)
    error_message = "deployment_type must be either 'hub' or 'spoke'."
  }
}

variable "deployment_phase" {
  description = "Phase of deployment: hub or spoke (alias for deployment_type)"
  type        = string
  default     = ""
}

variable "target_subscription_id" {
  description = "Target subscription ID for resource filtering"
  type        = string
  default     = ""
}

variable "tf_backend_resource_group" {
  description = "Resource group containing Terraform state storage"
  type        = string
  default     = ""
}

variable "tf_backend_storage_account" {
  description = "Storage account for Terraform state"
  type        = string
  default     = ""
}

variable "tf_backend_container" {
  description = "Container for Terraform state"
  type        = string
  default     = ""
}

# ============================================================================
# Local Configuration Processing
# ============================================================================

locals {
  # Load and parse configuration
  config_content = file(var.config_file)
  config = yamldecode(local.config_content)
  
  # Determine deployment type (support both deployment_type and deployment_phase)
  deployment_type = var.deployment_phase != "" ? var.deployment_phase : var.deployment_type
  
  # Extract subscription context
  current_subscription_id = data.azurerm_client_config.current.subscription_id
  
  # Deployment tags
  deployment_tags = {
    Environment     = var.environment_name
    DeploymentPhase = local.deployment_type
    ManagedBy       = "terraform-network"
    ConfigFile      = basename(var.config_file)
    DeployedBy      = data.azurerm_client_config.current.client_id
  }
}

# Data source for current subscription context
data "azurerm_client_config" "current" {}

# ============================================================================
# Network Module Deployment
# ============================================================================

module "network" {
  source = "../../modules/network"
  
  config                 = local.config
  deployment_type        = local.deployment_type
  target_subscription_id = var.target_subscription_id
  tf_backend_config = var.tf_backend_resource_group != "" ? {
    resource_group   = var.tf_backend_resource_group
    storage_account  = var.tf_backend_storage_account
    container        = var.tf_backend_container
  } : null
}

# ============================================================================
# Deployment Information
# ============================================================================

resource "null_resource" "deployment_info" {
  triggers = {
    config_file         = var.config_file
    environment_name    = var.environment_name
    deployment_type     = local.deployment_type
    subscription_id     = local.current_subscription_id
    config_hash         = sha256(local.config_content)
  }
  
  provisioner "local-exec" {
    command = "echo 'Deployed network ${local.deployment_type} for environment: ${var.environment_name} to subscription: ${local.current_subscription_id}'"
  }
}

# ============================================================================
# Outputs
# ============================================================================

output "deployment_info" {
  description = "Information about the deployment"
  value = {
    environment_name    = var.environment_name
    deployment_type     = local.deployment_type
    subscription_id     = local.current_subscription_id
    config_file         = var.config_file
    deployment_time     = timestamp()
  }
}

output "network_resources" {
  description = "Network resources created by the module"
  value       = module.network
  sensitive   = true
}