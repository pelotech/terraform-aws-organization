output "permission_set_arns" {
  description = "Permission set name => ARN."
  value       = { for name, permission_set in aws_ssoadmin_permission_set.this : name => permission_set.arn }
}
