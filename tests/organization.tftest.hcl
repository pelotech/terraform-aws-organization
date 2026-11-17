# Offline tests: mocked AWS provider, no credentials needed.
#   terraform init -backend=false && terraform test

mock_provider "aws" {
  mock_resource "aws_organizations_organization" {
    defaults = {
      roots = [{ id = "r-mock", arn = "arn:aws:organizations::111111111111:root/o-mock/r-mock", name = "Root", policy_types = [] }]
    }
  }
}

variables {
  trusted_services = ["sso.amazonaws.com"]
  organizational_units = [
    "Security",
    "Workloads",
    "Workloads/Prod",
  ]
}

run "defaults_create_only_the_organization" {
  command = plan

  variables {
    organizational_units = []
  }

  assert {
    condition     = aws_organizations_organization.this.feature_set == "ALL" && toset(aws_organizations_organization.this.enabled_policy_types) == toset(["SERVICE_CONTROL_POLICY"])
    error_message = "the organization should have all features and service control policies enabled by default"
  }

  assert {
    condition     = length(aws_organizations_organizational_unit.top) + length(aws_organizations_organizational_unit.nested) + length(aws_organizations_policy.this) + length(aws_organizations_account.this) == 0
    error_message = "no OU, policy or account unless asked for"
  }
}

run "ous_split_into_top_and_nested" {
  command = plan

  assert {
    condition     = toset(keys(aws_organizations_organizational_unit.top)) == toset(["Security", "Workloads"])
    error_message = "paths without a slash are top-level OUs"
  }

  assert {
    condition     = toset(keys(aws_organizations_organizational_unit.nested)) == toset(["Workloads/Prod"]) && aws_organizations_organizational_unit.nested["Workloads/Prod"].name == "Prod"
    error_message = "a Parent/Child path is a nested OU named after its last segment"
  }
}

run "nested_ou_needs_its_parent" {
  command = plan

  variables {
    organizational_units = ["Workloads/Prod"]
  }

  expect_failures = [var.organizational_units]
}

run "ous_nest_one_level_only" {
  command = plan

  variables {
    organizational_units = ["A", "A/B", "A/B/C"]
  }

  expect_failures = [var.organizational_units]
}

run "ou_paths_need_a_name_in_each_segment" {
  command = plan

  variables {
    organizational_units = ["A", "A/"]
  }

  expect_failures = [var.organizational_units]
}

run "a_top_level_ou_cannot_be_called_root" {
  command = plan

  variables {
    organizational_units = ["Root"]
  }

  expect_failures = [var.organizational_units]
}

run "policies_attach_by_name_to_root_and_ous" {
  command = plan

  variables {
    service_control_policies = {
      deny-leave-organization = ["Root", "Workloads"]
    }
  }

  assert {
    condition     = toset(keys(aws_organizations_policy.this)) == toset(["deny-leave-organization"]) && strcontains(aws_organizations_policy.this["deny-leave-organization"].content, "organizations:LeaveOrganization")
    error_message = "a named policy should be created from policies.tf"
  }

  assert {
    condition     = toset(keys(aws_organizations_policy_attachment.this)) == toset(["deny-leave-organization/Root", "deny-leave-organization/Workloads"])
    error_message = "one attachment per (policy, target)"
  }
}

run "accounts_with_an_email_are_managed" {
  command = plan

  variables {
    accounts = {
      management = { id = "111111111111" }
      security   = { email = "security@example.com", parent = "Security" }
      prod       = { email = "prod@example.com", name = "production", parent = "Workloads/Prod" }
    }
  }

  assert {
    condition     = toset(keys(aws_organizations_account.this)) == toset(["security", "prod"])
    error_message = "only accounts with an email become resources"
  }

  assert {
    condition     = aws_organizations_account.this["security"].name == "security" && aws_organizations_account.this["prod"].name == "production"
    error_message = "the account name defaults to the key and can be overridden"
  }

  assert {
    condition     = toset(keys(output.account_ids)) == toset(["management", "security", "prod"]) && output.account_ids["management"] == "111111111111"
    error_message = "every account should be in account_ids, a listed one under its declared ID"
  }
}

run "account_needs_an_id_or_an_email" {
  command = plan

  variables {
    accounts = {
      broken = {}
    }
  }

  expect_failures = [var.accounts]
}

run "account_cannot_have_both_an_id_and_an_email" {
  command = plan

  variables {
    accounts = {
      broken = { id = "222222222222", email = "security@example.com" }
    }
  }

  expect_failures = [var.accounts]
}

run "delegated_administrators_by_account_name" {
  command = plan

  variables {
    trusted_services = ["sso.amazonaws.com", "health.amazonaws.com", "securityhub.amazonaws.com"]
    accounts = {
      management = { id = "111111111111" }
      security   = { id = "222222222222" }
    }
    delegated_administrators = {
      security = ["health.amazonaws.com", "securityhub.amazonaws.com"]
    }
  }

  assert {
    condition     = toset(keys(aws_organizations_delegated_administrator.this)) == toset(["security/health.amazonaws.com", "security/securityhub.amazonaws.com"])
    error_message = "one delegation per (account, service)"
  }

  assert {
    condition     = aws_organizations_delegated_administrator.this["security/health.amazonaws.com"].account_id == "222222222222"
    error_message = "the account name should resolve to its ID"
  }
}

run "delegated_administrator_must_be_a_listed_account" {
  command = plan

  variables {
    delegated_administrators = {
      missing = ["health.amazonaws.com"]
    }
  }

  expect_failures = [var.delegated_administrators]
}

run "root_access_is_off_by_default" {
  command = plan

  assert {
    condition     = length(aws_iam_organizations_features.this) == 0 && toset(aws_organizations_organization.this.aws_service_access_principals) == toset(["sso.amazonaws.com"])
    error_message = "centralized root access should be off, and IAM should not be a trusted service, unless asked for"
  }
}

run "root_access_turns_on_both_features" {
  command = plan

  variables {
    trusted_services        = ["iam.amazonaws.com", "sso.amazonaws.com"]
    centralized_root_access = true
  }

  assert {
    condition     = toset(aws_iam_organizations_features.this[0].enabled_features) == toset(["RootCredentialsManagement", "RootSessions"])
    error_message = "both root access features should be enabled"
  }
}

run "root_access_needs_iam_trusted_access" {
  command = plan

  variables {
    centralized_root_access = true
  }

  expect_failures = [var.centralized_root_access]
}
