# Member accounts. An entry with an email is managed here (created or
# imported); an entry with an id is listed only so other code can look it up.

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
  # Account name => ID: the real ID of a managed account, the declared ID otherwise.
  account_ids = {
    for name, account in var.accounts :
    name => account.email != null ? aws_organizations_account.this[name].id : account.id
  }
}
