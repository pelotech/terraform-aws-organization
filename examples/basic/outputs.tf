output "organizational_unit_ids" {
  value       = module.organization.organizational_unit_ids
  description = "OU path => OU ID."
}

output "account_ids" {
  value       = module.organization.account_ids
  description = "Account name => account ID."
}
