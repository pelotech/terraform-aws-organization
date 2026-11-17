variable "trusted_services" {
  type        = set(string)
  description = "Service principals with trusted access, e.g. \"sso.amazonaws.com\". Authoritative: removing one turns its organization access off."
}

variable "centralized_root_access" {
  type        = bool
  default     = false
  description = "Turn on centralized root access (RootCredentialsManagement and RootSessions). Needs iam.amazonaws.com in trusted_services. Accounts the organization creates afterwards get no root credentials; existing accounts keep theirs."

  validation {
    condition     = !var.centralized_root_access || contains(var.trusted_services, "iam.amazonaws.com")
    error_message = "centralized_root_access needs \"iam.amazonaws.com\" in trusted_services."
  }
}

variable "enabled_policy_types" {
  type        = set(string)
  default     = ["SERVICE_CONTROL_POLICY"]
  description = "Policy types enabled on the root. Authoritative. When importing an organization, set it to what is live."
}

variable "organizational_units" {
  type        = set(string)
  default     = []
  description = "OU paths from the root: \"Name\" or \"Parent/Child\". A nested OU's parent must be listed too."

  validation {
    condition     = alltrue([for path in var.organizational_units : can(regex("^[^/]+(/[^/]+)?$", path))])
    error_message = "Each OU path is \"Name\" or \"Parent/Child\"."
  }

  validation {
    condition     = alltrue([for path in var.organizational_units : !strcontains(path, "/") || contains(var.organizational_units, dirname(path))])
    error_message = "A nested OU's parent must also be listed."
  }

  validation {
    condition     = !contains(var.organizational_units, "Root")
    error_message = "\"Root\" is the name for the organization root, so a top-level OU cannot be called \"Root\"."
  }
}

variable "service_control_policies" {
  type        = map(set(string))
  default     = {}
  description = "Policy name (see policies.tf) => where it attaches: \"Root\" or OU paths. OUs below a target inherit it."
}

variable "policies" {
  type = map(object({
    type        = optional(string, "SERVICE_CONTROL_POLICY")
    description = optional(string)
    content     = string
    targets     = set(string)
  }))
  default     = {}
  description = <<-EOT
    The organization's own policies, for anything the library in policies.tf doesn't cover. Policy name => settings:
      - type: SERVICE_CONTROL_POLICY (default), RESOURCE_CONTROL_POLICY, TAG_POLICY or another policy type. It must be in enabled_policy_types.
      - description: optional.
      - content: the policy document as JSON, for example from jsonencode or aws_iam_policy_document.
      - targets: where it attaches: "Root" or OU paths. OUs below a target inherit it.
  EOT

  validation {
    condition     = alltrue([for policy in values(var.policies) : contains(var.enabled_policy_types, policy.type)])
    error_message = "Each policy's type must be in enabled_policy_types."
  }

  validation {
    condition     = length(setintersection(keys(var.policies), keys(var.service_control_policies))) == 0
    error_message = "A policy name is used both here and in service_control_policies; rename one."
  }
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

variable "delegated_administrators" {
  type        = map(set(string))
  default     = {}
  description = "Account name (a key of accounts) => service principals it administers for the organization, e.g. { security = [\"health.amazonaws.com\"] }."

  validation {
    condition     = alltrue([for account in keys(var.delegated_administrators) : contains(keys(var.accounts), account)])
    error_message = "Each delegated administrator must be an account listed in accounts."
  }

  validation {
    condition     = alltrue([for service in flatten([for services in values(var.delegated_administrators) : tolist(services)]) : contains(var.trusted_services, service)])
    error_message = "Each delegated service must also be in trusted_services."
  }
}
