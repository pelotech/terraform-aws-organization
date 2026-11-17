# terraform-aws-organization

One AWS organization in code: its trusted services, organizational units (OUs), service control policies (SCPs) and member accounts. A submodule manages IAM Identity Center access.

[`modules/identity-center`](modules/identity-center/) manages permission sets and which group gets which permission set on which accounts.

Neither module declares a provider block or hardcodes a partition, so the same code works in commercial and GovCloud.

## How to run it

Apply it in the organization's **management account**.

- Pin `ref` to a [release tag](https://github.com/pelotech/terraform-aws-organization/releases).
- The organization and every managed account have `prevent_destroy`.
- `trusted_services` and `enabled_policy_types` are **authoritative**. Removing an entry turns it off for the whole organization; removing `sso.amazonaws.com` breaks Identity Center sign-in. Review every plan that touches them.

```hcl
module "organization" {
  source = "git::https://github.com/pelotech/terraform-aws-organization.git?ref=vX.Y.Z"

  trusted_services = ["sso.amazonaws.com"]

  organizational_units = [
    "Security",
    "Workloads",
    "Workloads/Prod",
    "Workloads/NonProd",
  ]

  service_control_policies = {
    deny-leave-organization = ["Workloads"]
  }

  accounts = {
    management = { id = "111111111111" }
    security   = { email = "aws-security@example.com", parent = "Security" }
    prod       = { email = "aws-prod@example.com", parent = "Workloads/Prod" }
  }
}

module "identity_center" {
  source = "git::https://github.com/pelotech/terraform-aws-organization.git//modules/identity-center?ref=vX.Y.Z"

  account_ids = module.organization.account_ids
  # permission_sets and access: see modules/identity-center
}
```

A complete example is in [`examples/basic`](examples/basic/).

## Organizational units (`organizational_units`)

A list of paths from the root. `"Name"` is a top-level OU and `"Parent/Child"` is nested under it; the parent must be listed too. One level of nesting is supported.

An OU exists to carry policy. Add one only when its accounts need different rules from the others.

## Service control policies (`service_control_policies`)

A map of policy name => where it attaches: `"Root"` or OU paths. OUs and accounts below a target inherit the policy. Service control policies never apply to the management account.

The policies and what each one does are defined in [`policies.tf`](policies.tf). To add one, add an entry to `local.policies` there.

## Accounts (`accounts`)

List every account once, including the management account. Each entry is name => settings, with exactly one of `id` and `email`:

- **`id`:** the account is listed so other code can look it up in the `account_ids` output. Nothing about it is managed.
- **`email`:** the account is managed here: its name (the key, or `name`), root email and parent OU (`parent`, default `"Root"`). The module creates the account unless you import it.

To move an account, change its `parent`; the account is moved in place. Changing a managed account's `email` forces a replacement, so treat root emails as fixed.

To stop managing an account, take it out of state first, then remove its entry or switch it to `id`:

```sh
terraform state rm 'module.organization.aws_organizations_account.this["prod"]'
```

Without that step the plan fails on `prevent_destroy`. A `removed` block cannot do this, because it cannot target one instance of a resource.

## Adopting an existing organization

Do it in two changes, so each plan is easy to check.

1. **Import the organization, changing nothing.** Set `trusted_services` and `enabled_policy_types` to exactly what is live, and add an `import` block:

   ```sh
   aws organizations list-aws-service-access-for-organization   # trusted_services
   aws organizations list-roots                                 # enabled_policy_types = Roots[0].PolicyTypes
   ```

   ```hcl
   import {
     to = module.organization.aws_organizations_organization.this
     id = "o-xxxxxxxxxx"
   }
   ```

   The plan must show `1 to import` and no change. `describe-organization` can report a policy type as available when the root has none enabled; use `list-roots`.

2. **Import accounts where they are.** Give each account its `email` exactly as it is in AWS, leave `parent` at the account's current place, and import it:

   ```hcl
   import {
     to = module.organization.aws_organizations_account.this["prod"]
     id = "333333333333"
   }
   ```

   The plan must show only imports. Accounts that were invited import the same way as accounts the organization created.

Then enable policy types, add OUs and policies, and move accounts in later changes. The first update to an imported account also writes `close_on_deletion = false` and `create_govcloud = false` into state; neither changes anything in AWS.

## Tests

The tests run offline against a mocked AWS provider, so they need no credentials:

```sh
terraform init -backend=false
terraform test
```

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
| [aws_organizations_account.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_account) | resource |
| [aws_organizations_organization.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_organization) | resource |
| [aws_organizations_organizational_unit.nested](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_organizational_unit) | resource |
| [aws_organizations_organizational_unit.top](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_organizational_unit) | resource |
| [aws_organizations_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_policy) | resource |
| [aws_organizations_policy_attachment.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_policy_attachment) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_accounts"></a> [accounts](#input\_accounts) | Account name => settings. List every account, including the management account.<br/>Set exactly one of id and email.<br/>  - id: the account ID, for an account that is only listed for lookup.<br/>  - email: root email, for an account managed here (created or imported).<br/>  - name: account name in AWS, when it differs from the key.<br/>  - parent: "Root" or an OU path. Only used for accounts managed here. | <pre>map(object({<br/>    id     = optional(string)<br/>    email  = optional(string)<br/>    name   = optional(string)<br/>    parent = optional(string, "Root")<br/>  }))</pre> | `{}` | no |
| <a name="input_enabled_policy_types"></a> [enabled\_policy\_types](#input\_enabled\_policy\_types) | Policy types enabled on the root. Authoritative. When importing an organization, set it to what is live. | `set(string)` | <pre>[<br/>  "SERVICE_CONTROL_POLICY"<br/>]</pre> | no |
| <a name="input_organizational_units"></a> [organizational\_units](#input\_organizational\_units) | OU paths from the root: "Name" or "Parent/Child". A nested OU's parent must be listed too. | `set(string)` | `[]` | no |
| <a name="input_service_control_policies"></a> [service\_control\_policies](#input\_service\_control\_policies) | Policy name (see policies.tf) => where it attaches: "Root" or OU paths. OUs below a target inherit it. | `map(set(string))` | `{}` | no |
| <a name="input_trusted_services"></a> [trusted\_services](#input\_trusted\_services) | Service principals with trusted access, e.g. "sso.amazonaws.com". Authoritative: removing one turns its organization access off. | `set(string)` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_account_ids"></a> [account\_ids](#output\_account\_ids) | Account name => account ID, for every account in var.accounts. |
| <a name="output_organizational_unit_ids"></a> [organizational\_unit\_ids](#output\_organizational\_unit\_ids) | OU path (for example Workloads/Prod) => OU ID. |
| <a name="output_root_id"></a> [root\_id](#output\_root\_id) | ID of the organization root. |
<!-- END_TF_DOCS -->
