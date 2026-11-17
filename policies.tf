# Organization policies. The library below holds service control policies
# (SCPs) that fit any organization unchanged; callers attach them by name with
# var.service_control_policies. Anything specific to one organization, or of
# another policy type, comes in through var.policies instead.

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

  # Library policies the caller picked, and the caller's own, in one shape.
  all_policies = merge(
    {
      for name, targets in var.service_control_policies : name => {
        type        = "SERVICE_CONTROL_POLICY"
        description = local.policies[name].description
        content     = jsonencode({ Version = "2012-10-17", Statement = local.policies[name].statements })
        targets     = targets
      }
    },
    var.policies,
  )

  # One entry per (policy, target), keyed "policy/target".
  policy_attachments = merge([
    for policy, settings in local.all_policies : {
      for target in settings.targets : "${policy}/${target}" => { policy = policy, target = target }
    }
  ]...)
}

resource "aws_organizations_policy" "this" {
  for_each    = local.all_policies
  name        = each.key
  description = each.value.description
  type        = each.value.type
  content     = each.value.content

  # The policy type must be enabled on the root first.
  depends_on = [aws_organizations_organization.this]
}

resource "aws_organizations_policy_attachment" "this" {
  for_each  = local.policy_attachments
  policy_id = aws_organizations_policy.this[each.value.policy].id
  target_id = local.target_ids[each.value.target]
}
