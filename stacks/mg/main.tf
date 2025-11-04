terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.100.0, < 4.0.0"
    }
  }

  # Backend configuration
  # Initialize with: terraform init -backend-config from workflow secrets
  backend "azurerm" {}
}

provider "azurerm" {
  features {}
  # subscription_id will be provided via ARM_SUBSCRIPTION_ID environment variable
  # For MG environments, this uses the dummy subscription ID from bootstrap config
}

locals {
  # Works everywhere (local + CI)
  config_path = abspath("${path.module}/../../configs/mg.yaml")
  cfg         = yamldecode(file(local.config_path))
}

# Optional guard without relying on fileexists()
resource "null_resource" "cfg_guard" {
  lifecycle {
    precondition {
      condition     = can(file(local.config_path))
      error_message = "Config file not found: ${local.config_path}"
    }
  }
}

module "mg" {
  source = "../../modules/mg"
  config = local.cfg
}

output "mg_ids" {
  value = module.mg.mg_ids
}

output "tree" {
  value = module.mg.tree
}

