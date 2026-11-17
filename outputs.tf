output "root_id" {
  description = "ID of the organization root."
  value       = local.root_id
}

output "organizational_unit_ids" {
  description = "OU path (for example Workloads/Prod) => OU ID."
  value       = local.organizational_unit_ids
}

output "account_ids" {
  description = "Account name => account ID, for every account in var.accounts."
  value       = local.account_ids
}
