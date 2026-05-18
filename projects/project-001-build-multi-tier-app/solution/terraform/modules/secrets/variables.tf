variable "secret_name" {
  description = "Name of the AWS Secrets Manager secret. Path-style names (e.g. multi-tier/db) are conventional for grouping related secrets."
  type        = string
  default     = "multi-tier/db"

  validation {
    condition     = can(regex("^[a-zA-Z0-9/_+=.@-]+$", var.secret_name))
    error_message = "Secret name must contain only alphanumeric characters and the characters /_+=.@-"
  }
}

variable "iam_user_name" {
  description = "Name of the IAM user that External Secrets Operator authenticates as."
  type        = string
  default     = "eso-multi-tier"
}

variable "recovery_window_in_days" {
  description = "Days AWS retains the secret after deletion before permanent removal. 0 forces immediate deletion (lab convenience). Production should use 30 (default)."
  type        = number
  default     = 7

  validation {
    condition     = var.recovery_window_in_days == 0 || (var.recovery_window_in_days >= 7 && var.recovery_window_in_days <= 30)
    error_message = "Recovery window must be 0 (immediate deletion) or between 7 and 30 days."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources. Merged with provider-level default_tags."
  type        = map(string)
  default     = {}
}
