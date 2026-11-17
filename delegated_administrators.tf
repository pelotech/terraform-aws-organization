# Accounts that administer an AWS service for the whole organization, so that
# work stays out of the management account.

locals {
  # One entry per (account, service), keyed "account/service".
  delegations = merge([
    for account, services in var.delegated_administrators : {
      for service in services : "${account}/${service}" => { account = account, service = service }
    }
  ]...)
}

resource "aws_organizations_delegated_administrator" "this" {
  for_each          = local.delegations
  account_id        = local.account_ids[each.value.account]
  service_principal = each.value.service

  # The service's trusted access is enabled on the organization first.
  depends_on = [aws_organizations_organization.this]
}
