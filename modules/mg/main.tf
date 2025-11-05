terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.100.0, < 4.0.0"
    }
  }
}

data "azurerm_client_config" "current" {}

# =========================
# MG resources by depth (acyclic)
# =========================

# Level 0: root-only parent
resource "azurerm_management_group" "mg_l0" {
  for_each     = local.level0
  name         = each.key
  display_name = each.value.display_name
  parent_management_group_id = null
}

# Level 1..6: parent is always in the previous level
resource "azurerm_management_group" "mg_l1" {
  for_each     = local.level1
  name         = each.key
  display_name = each.value.display_name
  parent_management_group_id = azurerm_management_group.mg_l0[each.value.parent_id].id
}

resource "azurerm_management_group" "mg_l2" {
  for_each     = local.level2
  name         = each.key
  display_name = each.value.display_name
  parent_management_group_id = azurerm_management_group.mg_l1[each.value.parent_id].id
}

resource "azurerm_management_group" "mg_l3" {
  for_each     = local.level3
  name         = each.key
  display_name = each.value.display_name
  parent_management_group_id = azurerm_management_group.mg_l2[each.value.parent_id].id
}

resource "azurerm_management_group" "mg_l4" {
  for_each     = local.level4
  name         = each.key
  display_name = each.value.display_name
  parent_management_group_id = azurerm_management_group.mg_l3[each.value.parent_id].id
}

resource "azurerm_management_group" "mg_l5" {
  for_each     = local.level5
  name         = each.key
  display_name = each.value.display_name
  parent_management_group_id = azurerm_management_group.mg_l4[each.value.parent_id].id
}

resource "azurerm_management_group" "mg_l6" {
  for_each     = local.level6
  name         = each.key
  display_name = each.value.display_name
  parent_management_group_id = azurerm_management_group.mg_l5[each.value.parent_id].id
}

# =========================
# Subscription -> MG associations
# (iterate only attachments whose target MG will exist post-plan)
# =========================
resource "azurerm_management_group_subscription_association" "attach" {
  for_each = {
    for a in local.sub_input :
    "${a.subscription_id}::${a.target_mg_id}" => a
    if contains(keys(local.mg_all), a.target_mg_id)
  }
  management_group_id = local.mg_all[each.value.target_mg_id].arm_id
  subscription_id     = "/subscriptions/${each.value.subscription_id}"
}
