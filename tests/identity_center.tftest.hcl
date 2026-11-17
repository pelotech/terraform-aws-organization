# Offline tests for modules/identity-center: mocked AWS provider, no credentials needed.

mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = {
      partition = "aws-us-gov"
    }
  }
  mock_data "aws_ssoadmin_instances" {
    defaults = {
      arns               = ["arn:aws-us-gov:sso:::instance/ssoins-0000000000000000"]
      identity_store_ids = ["d-0000000000"]
    }
  }
  # Assignments validate the group ID format.
  mock_data "aws_identitystore_group" {
    defaults = {
      group_id = "11111111-2222-3333-4444-555555555555"
    }
  }
  mock_resource "aws_ssoadmin_permission_set" {
    defaults = {
      arn = "arn:aws-us-gov:sso:::permissionSet/ssoins-0000000000000000/ps-0000000000000000"
    }
  }
}

variables {
  account_ids = {
    management = "111111111111"
    workloads  = "222222222222"
  }
  permission_sets = {
    AdministratorAccess = {
      description      = "Full access"
      session_duration = "PT4H"
      policies         = ["AdministratorAccess"]
    }
    Operator = {
      description      = "Read plus support"
      session_duration = "PT8H"
      policies         = ["ReadOnlyAccess", "AWSSupportAccess"]
    }
  }
  access = {
    admins    = { AdministratorAccess = ["workloads"] }
    operators = { Operator = ["management", "workloads"] }
  }
}

run "one_resource_per_policy_and_assignment" {
  command = plan

  module {
    source = "./modules/identity-center"
  }

  assert {
    condition     = toset(keys(aws_ssoadmin_permission_set.this)) == toset(["AdministratorAccess", "Operator"])
    error_message = "one permission set per entry"
  }

  assert {
    condition     = toset(keys(aws_ssoadmin_managed_policy_attachment.this)) == toset(["AdministratorAccess/AdministratorAccess", "Operator/ReadOnlyAccess", "Operator/AWSSupportAccess"])
    error_message = "one attachment per (permission set, policy)"
  }

  assert {
    condition     = toset(keys(aws_ssoadmin_account_assignment.this)) == toset(["admins/AdministratorAccess/workloads", "operators/Operator/management", "operators/Operator/workloads"])
    error_message = "one assignment per (group, permission set, account)"
  }
}

run "policies_and_accounts_resolve" {
  command = plan

  module {
    source = "./modules/identity-center"
  }

  assert {
    condition     = aws_ssoadmin_managed_policy_attachment.this["Operator/AWSSupportAccess"].managed_policy_arn == "arn:aws-us-gov:iam::aws:policy/AWSSupportAccess"
    error_message = "managed policy ARNs should use the current partition"
  }

  assert {
    condition     = aws_ssoadmin_account_assignment.this["operators/Operator/management"].target_id == "111111111111"
    error_message = "account names should resolve through account_ids"
  }
}
