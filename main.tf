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

locals {
  root_id = aws_organizations_organization.this.roots[0].id

  # OU path => ID.
  organizational_unit_ids = {
    for path, ou in merge(aws_organizations_organizational_unit.top, aws_organizations_organizational_unit.nested) : path => ou.id
  }

  # Anything a policy can attach to: "Root" or an OU path => ID.
  target_ids = merge({ Root = local.root_id }, local.organizational_unit_ids)
}
