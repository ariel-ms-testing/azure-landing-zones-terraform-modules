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