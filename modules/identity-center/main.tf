# IAM Identity Center permission sets and group assignments, applied in the
# account that holds the Identity Center instance.

locals {
  # One entry per (permission set, policy), keyed "PermissionSet/Policy".
  permission_set_policies = merge([
    for permission_set, settings in var.permission_sets : {
      for policy in settings.policies : "${permission_set}/${policy}" => { permission_set = permission_set, policy = policy }
    }
  ]...)

  # One entry per (group, permission set, account), keyed "group/PermissionSet/account".
  assignments = merge(flatten([
    for group, sets in var.access : [
      for permission_set, accounts in sets : {
        for account in accounts : "${group}/${permission_set}/${account}" => { group = group, permission_set = permission_set, account = account }
      }
    ]
  ])...)

  instance_arn      = one(data.aws_ssoadmin_instances.this.arns)
  identity_store_id = one(data.aws_ssoadmin_instances.this.identity_store_ids)
}

data "aws_partition" "current" {}

data "aws_ssoadmin_instances" "this" {}

# Groups are looked up by display name; they are not created here.
data "aws_identitystore_group" "this" {
  for_each          = var.access
  identity_store_id = local.identity_store_id
  alternate_identifier {
    unique_attribute {
      attribute_path  = "DisplayName"
      attribute_value = each.key
    }
  }
}

resource "aws_ssoadmin_permission_set" "this" {
  for_each         = var.permission_sets
  name             = each.key
  description      = each.value.description
  session_duration = each.value.session_duration
  instance_arn     = local.instance_arn
}

resource "aws_ssoadmin_managed_policy_attachment" "this" {
  for_each           = local.permission_set_policies
  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.value.permission_set].arn
  managed_policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/${each.value.policy}"
}

resource "aws_ssoadmin_account_assignment" "this" {
  for_each           = local.assignments
  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.value.permission_set].arn
  principal_type     = "GROUP"
  principal_id       = data.aws_identitystore_group.this[each.value.group].group_id
  target_type        = "AWS_ACCOUNT"
  target_id          = var.account_ids[each.value.account]
}
