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