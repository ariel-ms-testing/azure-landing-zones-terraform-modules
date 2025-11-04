variable "config" {
  description = "Decoded mg.yaml content"
  type = object({
    schema_version    = number
    management_groups = list(object({
      id           = string
      display_name = string
      parent_id    = string            # 'root' or another mg id (by id)
      subscriptions = optional(list(string), [])  # subscription GUIDs
    }))
  })

  validation {
    condition     = var.config.schema_version == 1
    error_message = "Unsupported schema_version (expected 1)."
  }
}
