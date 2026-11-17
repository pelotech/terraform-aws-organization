# One AWS organization, applied in its management account.

resource "aws_organizations_organization" "this" {
  feature_set                   = "ALL"
  aws_service_access_principals = var.trusted_services
  enabled_policy_types          = var.enabled_policy_types

  lifecycle {
    prevent_destroy = true
  }
}

# OUs: one resource per level, so one level of nesting.
resource "aws_organizations_organizational_unit" "top" {
  for_each  = toset([for path in var.organizational_units : path if !strcontains(path, "/")])
  name      = each.key
  parent_id = local.root_id
}

resource "aws_organizations_organizational_unit" "nested" {
  for_each  = toset([for path in var.organizational_units : path if strcontains(path, "/")])
  name      = basename(each.key)
  parent_id = aws_organizations_organizational_unit.top[dirname(each.key)].id
}

# Centralized root access: accounts the organization creates get no root
# credentials, and the management account (or a delegated administrator) can run
# the few tasks that need root in a member account.
resource "aws_iam_organizations_features" "this" {
  count            = var.centralized_root_access ? 1 : 0
  enabled_features = ["RootCredentialsManagement", "RootSessions"]

  # Needs iam.amazonaws.com trusted access first.
  depends_on = [aws_organizations_organization.this]
}

locals {
  root_id = aws_organizations_organization.this.roots[0].id

  # OU path => ID.
  organizational_unit_ids = {
    for path, ou in merge(aws_organizations_organizational_unit.top, aws_organizations_organizational_unit.nested) : path => ou.id
  }

  # Anything a policy can attach to: "Root" or an OU path => ID.
  target_ids = merge({ Root = local.root_id }, local.organizational_unit_ids)
}
