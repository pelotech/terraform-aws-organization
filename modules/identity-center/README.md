# identity-center

IAM Identity Center access in code: permission sets, and which group gets which permission set on which accounts. Apply it in the account that holds the Identity Center instance (the management account, or its delegated administrator).

Groups are looked up by display name in the identity store. They are not created here.

```hcl
module "identity_center" {
  source = "git::https://github.com/pelotech/terraform-aws-organization.git//modules/identity-center?ref=vX.Y.Z"

  # Account name => account ID. Usually from the organization module, so accounts are listed once.
  account_ids = module.organization.account_ids

  permission_sets = {
    ReadOnlyAccess = {
      description      = "Read only access"
      session_duration = "PT12H"
      managed_policies = ["ReadOnlyAccess"]
    }
  }

  # Group => permission set => account names.
  access = {
    aws-read-only = { ReadOnlyAccess = ["management", "prod"] }
  }
}
```

`managed_policies` are the names of AWS-managed policies. Customer-managed and inline policies are not supported.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_ssoadmin_account_assignment.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssoadmin_account_assignment) | resource |
| [aws_ssoadmin_managed_policy_attachment.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssoadmin_managed_policy_attachment) | resource |
| [aws_ssoadmin_permission_set.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssoadmin_permission_set) | resource |
| [aws_identitystore_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/identitystore_group) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_ssoadmin_instances.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ssoadmin_instances) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_access"></a> [access](#input\_access) | Group display name => permission set name => account names it is granted on. Groups must already exist in the identity store. | `map(map(set(string)))` | n/a | yes |
| <a name="input_account_ids"></a> [account\_ids](#input\_account\_ids) | Account name => account ID. The names are what `access` refers to. | `map(string)` | n/a | yes |
| <a name="input_permission_sets"></a> [permission\_sets](#input\_permission\_sets) | Permission set name => settings. `session_duration` is ISO 8601 ("PT8H"); `managed_policies` are AWS-managed policy names. | <pre>map(object({<br/>    description      = string<br/>    session_duration = string<br/>    managed_policies = set(string)<br/>  }))</pre> | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_permission_set_arns"></a> [permission\_set\_arns](#output\_permission\_set\_arns) | Permission set name => ARN. |
<!-- END_TF_DOCS -->
