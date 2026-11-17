# Member accounts. An entry with an email is managed here (created or
# imported); the rest are listed only so other code can look up their IDs.

resource "aws_organizations_account" "this" {
  for_each  = { for name, account in var.accounts : name => account if account.email != null }
  name      = coalesce(each.value.name, each.key)
  email     = each.value.email
  parent_id = local.target_ids[each.value.parent]

  lifecycle {
    prevent_destroy = true
  }
}

locals {
  # Account name => ID. A declared ID wins, so it is known at plan time.
  account_ids = {
    for name, account in var.accounts :
    name => account.id != null ? account.id : aws_organizations_account.this[name].id
  }
}
