# Service control policies (SCPs). To add one, add it to `policies`; callers
# attach it by name with var.service_control_policies.

locals {
  policies = {
    deny-leave-organization = {
      description = "Accounts cannot remove themselves from the organization."
      statements = [{
        Sid      = "DenyLeaveOrganization"
        Effect   = "Deny"
        Action   = "organizations:LeaveOrganization"
        Resource = "*"
      }]
    }
  }

  # One entry per (policy, target), keyed "policy/target".
  policy_attachments = merge([
    for policy, targets in var.service_control_policies : {
      for target in targets : "${policy}/${target}" => { policy = policy, target = target }
    }
  ]...)
}

resource "aws_organizations_policy" "this" {
  for_each    = var.service_control_policies
  name        = each.key
  description = local.policies[each.key].description
  type        = "SERVICE_CONTROL_POLICY"
  content     = jsonencode({ Version = "2012-10-17", Statement = local.policies[each.key].statements })

  # The policy type must be enabled on the root first.
  depends_on = [aws_organizations_organization.this]
}

resource "aws_organizations_policy_attachment" "this" {
  for_each  = local.policy_attachments
  policy_id = aws_organizations_policy.this[each.value.policy].id
  target_id = local.target_ids[each.value.target]
}
