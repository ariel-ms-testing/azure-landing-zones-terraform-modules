variable "tenant_id" {
  description = "Azure AD tenant ID (can be overridden, otherwise read from bootstrap.yaml)"
  type        = string
  default     = null
}

variable "tfstate_subscription_id" {
  description = "Subscription ID for Terraform state (can be overridden, otherwise read from bootstrap.yaml)"
  type        = string
  default     = null
}

variable "github_owner" {
  description = "GitHub owner (can be overridden, otherwise read from bootstrap.yaml)"
  type        = string
  default     = null
}