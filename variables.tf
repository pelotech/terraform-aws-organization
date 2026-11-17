variable "trusted_services" {
  type        = list(string)
  description = "Service principals with trusted access, e.g. \"sso.amazonaws.com\". Authoritative: removing one turns its organization access off."
}

variable "enabled_policy_types" {
  type        = list(string)
  default     = ["SERVICE_CONTROL_POLICY"]
  description = "Policy types enabled on the root. Authoritative. When importing an organization, set it to what is live."
}

variable "organizational_units" {
  type        = list(string)
  default     = []
  description = "OU paths from the root: \"Name\" or \"Parent/Child\". A nested OU's parent must be listed too."

  validation {
    condition = alltrue([
      for path in var.organizational_units :
      length(split("/", path)) <= 2 && (!strcontains(path, "/") || contains(var.organizational_units, dirname(path)))
    ])
    error_message = "Each OU path is \"Name\" or \"Parent/Child\", and a nested OU's parent must also be listed."
  }
}

variable "service_control_policies" {
  type        = map(list(string))
  default     = {}
  description = "Policy name (see policies.tf) => where it attaches: \"Root\" or OU paths. OUs below a target inherit it."
}

variable "accounts" {
  type = map(object({
    id     = optional(string)
    email  = optional(string)
    name   = optional(string)
    parent = optional(string, "Root")
  }))
  default     = {}
  description = <<-EOT
    Account name => settings. List every account, including the management account.
    Set exactly one of id and email.
      - id: the account ID, for an account that is only listed for lookup.
      - email: root email, for an account managed here (created or imported).
      - name: account name in AWS, when it differs from the key.
      - parent: "Root" or an OU path. Only used for accounts managed here.
  EOT

  validation {
    condition     = alltrue([for account in values(var.accounts) : (account.id == null) != (account.email == null)])
    error_message = "Set id (listed for lookup only) or email (managed here) on each account, not both."
  }
}
