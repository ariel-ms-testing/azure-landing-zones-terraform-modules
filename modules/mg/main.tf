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
# Input normalization
# =========================
locals {
  # MGs (or empty)
  mg_input = coalesce(try(var.config.management_groups, null), [])

  # Nested subscriptions: management_groups[*].subscriptions: [ "<sub-guid>", ... ]
  sub_input = flatten([
    for mg in local.mg_input : [
      for sid in coalesce(try(mg.subscriptions, null), []) : {
        subscription_id = trimspace(lower(sid))
        target_mg_id    = mg.id
      }
    ]
  ])

  # Index MGs by id
  mg_map = { for mg in local.mg_input : mg.id => mg }

  # Helper for duplicate subscription detection
  all_subscription_ids = [for a in local.sub_input : a.subscription_id]
  duplicate_subscription_ids = setsubtract(
    toset(local.all_subscription_ids),
    toset(distinct(local.all_subscription_ids))
  )

  # =========================
  # Depth bucketing (root-only for level0)
  # =========================
  level0 = {
    for id, mg in local.mg_map :
    id => mg if (mg.parent_id == "root")
  }
  level1 = { for id, mg in local.mg_map : id => mg if contains(keys(local.level0), mg.parent_id) }
  level2 = { for id, mg in local.mg_map : id => mg if contains(keys(local.level1), mg.parent_id) }
  level3 = { for id, mg in local.mg_map : id => mg if contains(keys(local.level2), mg.parent_id) }
  level4 = { for id, mg in local.mg_map : id => mg if contains(keys(local.level3), mg.parent_id) }
  level5 = { for id, mg in local.mg_map : id => mg if contains(keys(local.level4), mg.parent_id) }
  level6 = { for id, mg in local.mg_map : id => mg if contains(keys(local.level5), mg.parent_id) }
}

# =========================
# Guards
# =========================

# All non-root parents must exist in this file
resource "null_resource" "parent_guard" {
  lifecycle {
    precondition {
      condition = length([
        for mg in local.mg_input : mg
        if (mg.parent_id != "root" && !contains(keys(local.mg_map), mg.parent_id))
      ]) == 0

      error_message = format(
        "A management group points to a parent that isn't in this file.\n\nProblem:\n%s\n\nWhy this happens:\n- You deleted/renamed a parent MG but left its children.\n\nHow to fix (pick one):\n- Move the child to an existing parent in mg.yaml (change child.parent_id), OR\n- Add the missing parent back to mg.yaml.\n\nThen run terraform plan again.",
        join(
          "\n",
          [
            for mg in local.mg_input :
            format("  • child '%s' → missing parent '%s'", mg.id, mg.parent_id)
            if (mg.parent_id != "root" && !contains(keys(local.mg_map), mg.parent_id))
          ]
        )
      )
    }
  }
}

resource "null_resource" "dup_mg_id_guard" {
  lifecycle {
    precondition {
      condition = length(local.mg_input) == length(distinct([for mg in local.mg_input : mg.id]))
      error_message = "Duplicate management_group ids in mg.yaml. Each MG id must be unique."
    }
  }
}

# Guard: hierarchy depth must be <= 6 (root + 6 levels)
resource "null_resource" "depth_guard" {
  lifecycle {
    precondition {
      # Union of all placed MG ids (level0..level6)
      condition = length(setsubtract(
        toset(keys(local.mg_map)),
        toset(concat(
          keys(local.level0),
          keys(local.level1),
          keys(local.level2),
          keys(local.level3),
          keys(local.level4),
          keys(local.level5),
          keys(local.level6)
        ))
      )) == 0

      error_message = format(
        "Management group hierarchy exceeds 6 levels from root.\n\nToo-deep nodes:\n%s\n\nFix:\n- Reduce nesting so no chain from 'root' exceeds 6 MG levels.",
        join("\n",
          [
            for id in setsubtract(
              toset(keys(local.mg_map)),
              toset(concat(
                keys(local.level0),
                keys(local.level1),
                keys(local.level2),
                keys(local.level3),
                keys(local.level4),
                keys(local.level5),
                keys(local.level6)
              ))
            ) : "  • " + id
          ]
        )
      )
    }
  }
}



# Subscription GUID format (basic typo catcher)
resource "null_resource" "sub_guid_guard" {
  lifecycle {
    precondition {
      condition = length([
        for a in local.sub_input : a
        if !can(regex("^([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$", a.subscription_id))
      ]) == 0
      error_message = "One or more subscriptions are not valid GUIDs. Check the 'subscriptions' lists under each MG."
    }
  }
}

# Prevent the same subscription appearing under multiple MGs
resource "null_resource" "dup_sub_guard" {
  lifecycle {
    precondition {
      condition = length(local.sub_input) == length(distinct(local.all_subscription_ids))
      error_message = format(
        "A subscription appears under multiple management groups.\n\nProblem:\n%s\n\nFix:\n- A subscription can be attached to only one MG. Remove duplicates so each subscription appears under a single MG.",
        join(
          "\n",
          [for sid in local.duplicate_subscription_ids : "  • ${sid}"]
        )
      )
    }
  }
}

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
# Unified MG view (outputs + wiring)
# =========================
locals {
  # Merge all resource instances, then project to a compact node shape
  mg_all = {
    for id, r in merge(
      { for k, v in azurerm_management_group.mg_l0 : k => v },
      { for k, v in azurerm_management_group.mg_l1 : k => v },
      { for k, v in azurerm_management_group.mg_l2 : k => v },
      { for k, v in azurerm_management_group.mg_l3 : k => v },
      { for k, v in azurerm_management_group.mg_l4 : k => v },
      { for k, v in azurerm_management_group.mg_l5 : k => v },
      { for k, v in azurerm_management_group.mg_l6 : k => v }
    ) : id => {
      arm_id       = r.id
      display_name = r.display_name
      parent_id    = try(r.parent_management_group_id, null)
    }
  }

  # Subscriptions grouped by MG (only for MGs that will exist post-plan)
  subs_by_mg = {
    for mg_id in keys(local.mg_all) :
    mg_id => [
      for a in local.sub_input :
      a.subscription_id
      if a.target_mg_id == mg_id && contains(keys(local.mg_all), a.target_mg_id)
    ]
  }
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
