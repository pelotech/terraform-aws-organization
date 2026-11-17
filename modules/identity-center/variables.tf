variable "account_ids" {
  type        = map(string)
  description = "Account name => account ID. The names are what `access` refers to."
}

variable "permission_sets" {
  type = map(object({
    description      = string
    session_duration = string
    managed_policies = optional(set(string), [])
    inline_policy    = optional(string)
  }))
  description = "Permission set name => settings. `session_duration` is ISO 8601 (\"PT8H\"); `managed_policies` are AWS-managed policy names; `inline_policy` is an IAM policy JSON document, for permissions no managed policy covers narrowly enough."
}

variable "access" {
  type        = map(map(set(string)))
  description = "Group display name => permission set name => account names it is granted on. Groups must already exist in the identity store."
}
