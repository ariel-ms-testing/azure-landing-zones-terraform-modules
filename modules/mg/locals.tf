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

  # =========================
  # Unified MG view (outputs + wiring)
  # =========================
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