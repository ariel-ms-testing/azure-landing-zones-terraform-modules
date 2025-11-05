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