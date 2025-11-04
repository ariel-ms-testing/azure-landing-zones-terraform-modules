output "mg_ids" {
  description = "Map: management group id -> ARM resource id"
  value       = { for id, n in local.mg_all : id => n.arm_id }
}

output "tree" {
  description = "Flat view of created MGs with subscription attachments"
  value = [
    for id in sort(keys(local.mg_all)) : {
      id            = id
      display_name  = local.mg_all[id].display_name
      parent_id     = local.mg_all[id].parent_id
      subscriptions = lookup(local.subs_by_mg, id, [])
    }
  ]
}
