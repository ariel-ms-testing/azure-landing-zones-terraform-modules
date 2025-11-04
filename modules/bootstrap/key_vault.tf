# Key Vault for storing bootstrap secrets
resource "azurerm_key_vault" "bootstrap" {
  name                = var.bootstrap.key_vault.name
  location            = var.tfstate.location
  resource_group_name = var.tfstate.resource_group
  tenant_id           = data.azuread_client_config.current.tenant_id
  
  # Standard tier for basic secret storage
  sku_name = "standard"
  
  # Use RBAC for authorization instead of access policies
  rbac_authorization_enabled = true
  
  # Network access - restrict to deployment networks
  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
    
    # Allow access from deployment networks
    ip_rules = var.bootstrap.key_vault.allowed_ips
    virtual_network_subnet_ids = var.bootstrap.key_vault.allowed_subnets
  }
  
  # Enable for deployment
  enabled_for_deployment          = false
  enabled_for_disk_encryption     = false
  enabled_for_template_deployment = true
  
  # Purge protection for production
  purge_protection_enabled = var.bootstrap.key_vault.purge_protection
  soft_delete_retention_days = 90
  
  tags = var.tags
}

# RBAC role assignment for the current user/service principal running bootstrap
resource "azurerm_role_assignment" "bootstrap_admin_kv" {
  scope                = azurerm_key_vault.bootstrap.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azuread_client_config.current.object_id
}

# RBAC role assignments for created service principals (read-only)
resource "azurerm_role_assignment" "service_principals_kv" {
  for_each = azuread_service_principal.landing_zones
  
  scope                = azurerm_key_vault.bootstrap.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = each.value.object_id
}

# Store client secrets in Key Vault (if created)
resource "azurerm_key_vault_secret" "client_secrets" {
  for_each = local.create_client_secrets ? azuread_application_password.landing_zones : {}
  
  name         = "sp-${each.key}-secret"
  value        = each.value.value
  key_vault_id = azurerm_key_vault.bootstrap.id
  
  # Expire before the actual secret expires
  expiration_date = timeadd(each.value.end_date, "-24h")
  
  content_type = "text/plain"
  
  tags = merge(var.tags, {
    Environment = each.key
    SecretType  = "ServicePrincipalSecret"
  })
  
  depends_on = [azurerm_role_assignment.bootstrap_admin_kv]
}

# Store service principal application IDs
resource "azurerm_key_vault_secret" "client_ids" {
  for_each = azuread_application.landing_zones
  
  name         = "sp-${each.key}-client-id"
  value        = each.value.client_id
  key_vault_id = azurerm_key_vault.bootstrap.id
  
  content_type = "text/plain"
  
  tags = merge(var.tags, {
    Environment = each.key
    SecretType  = "ServicePrincipalClientId"
  })
  
  depends_on = [azurerm_role_assignment.bootstrap_admin_kv]
}