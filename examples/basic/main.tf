# The organization's management account, with admin credentials.
provider "aws" {
  region = "us-west-2"
}

module "organization" {
  source = "../.."

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
    security   = { id = "222222222222", email = "aws-security@example.com", parent = "Security" }
    prod       = { id = "333333333333", email = "aws-prod@example.com", parent = "Workloads/Prod" }
    # No id: the module creates this account.
    nonprod = { email = "aws-nonprod@example.com", parent = "Workloads/NonProd" }
  }
}

module "identity_center" {
  source = "../../modules/identity-center"

  account_ids = module.organization.account_ids

  permission_sets = {
    AdministratorAccess = {
      description      = "Full access"
      session_duration = "PT4H"
      policies         = ["AdministratorAccess"]
    }
    ReadOnlyAccess = {
      description      = "Read only access"
      session_duration = "PT12H"
      policies         = ["ReadOnlyAccess"]
    }
  }

  access = {
    aws-administrators = { AdministratorAccess = ["prod", "nonprod"] }
    aws-read-only      = { ReadOnlyAccess = ["management", "security", "prod", "nonprod"] }
  }
}
