# Offline tests for modules/risk-alerts: mocked AWS provider, no credentials needed.

mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }
  # The topic module combines policy documents; mocks need valid JSON.
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{}"
    }
  }
  # The event targets validate their ARNs.
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::222222222222:role/mock"
    }
  }
  mock_resource "aws_cloudwatch_event_connection" {
    defaults = {
      arn = "arn:aws:events:us-east-1:222222222222:connection/mock/11111111-1111-1111-1111-111111111111"
    }
  }
  mock_resource "aws_cloudwatch_event_api_destination" {
    defaults = {
      arn = "arn:aws:events:us-east-1:222222222222:api-destination/mock/11111111-1111-1111-1111-111111111111"
    }
  }
  mock_resource "aws_lambda_function" {
    defaults = {
      arn = "arn:aws-us-gov:lambda:us-gov-west-1:222222222222:function:health-risk-alerts-forwarder"
    }
  }
  mock_resource "aws_sns_topic" {
    defaults = {
      arn = "arn:aws:sns:us-east-1:222222222222:health-risk-alerts"
    }
  }
}

run "rule_and_topic" {
  command = plan

  module {
    source = "./modules/risk-alerts"
  }

  variables {
    email_endpoints = ["incidents@example.com"]
  }

  assert {
    condition     = aws_cloudwatch_event_rule.this.region == "us-east-1" && aws_cloudwatch_event_target.topic.region == "us-east-1"
    error_message = "commercial rule and target should be in us-east-1, where AWS Health sends these events"
  }

  assert {
    condition     = jsondecode(aws_cloudwatch_event_rule.this.event_pattern).detail.service == ["RISK"]
    error_message = "rule should match AWS Health RISK events"
  }

  assert {
    condition     = keys(module.topic.subscriptions) == ["incidents@example.com"]
    error_message = "one email subscription per endpoint"
  }

  assert {
    condition     = length(aws_cloudwatch_event_connection.webhook) + length(aws_iam_role.webhook) + length(aws_cloudwatch_event_target.webhook) + length(aws_lambda_function.forwarder) == 0
    error_message = "no webhook_urls should create no connection, role, webhook target or forwarder"
  }
}

run "webhooks_use_api_destinations" {
  command = plan

  module {
    source = "./modules/risk-alerts"
  }

  variables {
    webhook_urls = {
      secops-chat  = sensitive("https://chat.googleapis.com/v1/spaces/AAAA/messages?key=k&token=t")
      secops-slack = sensitive("https://hooks.slack.com/services/T000/B000/XXXX")
    }
  }

  assert {
    condition     = keys(aws_cloudwatch_event_api_destination.webhook) == ["secops-chat", "secops-slack"]
    error_message = "one API destination per webhook"
  }

  assert {
    condition     = aws_cloudwatch_event_api_destination.webhook["secops-slack"].name == "health-risk-alerts-secops-slack" && aws_cloudwatch_event_api_destination.webhook["secops-slack"].http_method == "POST"
    error_message = "API destination should POST and be named after the webhook"
  }

  assert {
    condition     = length(aws_cloudwatch_event_connection.webhook) == 1 && length(aws_iam_role.webhook) == 1
    error_message = "webhooks share one connection and one role"
  }

  assert {
    condition     = strcontains(jsondecode(aws_cloudwatch_event_target.webhook["secops-chat"].input_transformer[0].input_template).text, "<type>")
    error_message = "webhook body should be JSON with a text field holding unescaped placeholders"
  }

  assert {
    condition     = length(aws_lambda_function.forwarder) == 0
    error_message = "no forwarder where API destinations exist"
  }
}

run "webhook_urls_must_be_https" {
  command = plan

  module {
    source = "./modules/risk-alerts"
  }

  variables {
    webhook_urls = {
      chat = "http://example.com/hook"
    }
  }

  expect_failures = [var.webhook_urls]
}

run "govcloud_region" {
  command = plan

  module {
    source = "./modules/risk-alerts"
  }

  override_data {
    target = data.aws_partition.current
    values = {
      partition = "aws-us-gov"
    }
  }

  variables {
    email_endpoints = ["incidents@example.com"]
  }

  assert {
    condition     = aws_cloudwatch_event_rule.this.region == "us-gov-west-1" && aws_cloudwatch_event_target.topic.region == "us-gov-west-1"
    error_message = "GovCloud rule and target should be in us-gov-west-1"
  }

  assert {
    condition     = length(aws_lambda_function.forwarder) == 0 && length(aws_iam_role.forwarder) == 0
    error_message = "no forwarder without webhook_urls"
  }
}

run "govcloud_webhooks_use_the_forwarder" {
  command = plan

  module {
    source = "./modules/risk-alerts"
  }

  # GovCloud has no API destinations.
  override_data {
    target = data.aws_partition.current
    values = {
      partition = "aws-us-gov"
    }
  }

  variables {
    webhook_urls = {
      secops-chat  = sensitive("https://chat.googleapis.com/v1/spaces/AAAA/messages?key=k&token=t")
      secops-slack = sensitive("https://hooks.slack.com/services/T000/B000/XXXX")
    }
  }

  assert {
    condition     = length(aws_lambda_function.forwarder) == 1 && aws_lambda_function.forwarder[0].region == "us-gov-west-1"
    error_message = "GovCloud webhooks should go through one Lambda in us-gov-west-1"
  }

  assert {
    condition     = toset(keys(jsondecode(nonsensitive(aws_lambda_function.forwarder[0].environment[0].variables.WEBHOOK_URLS)))) == toset(["secops-chat", "secops-slack"])
    error_message = "the forwarder should be given every webhook"
  }

  assert {
    condition     = aws_cloudwatch_event_target.forwarder[0].input_transformer[0].input_template == local.webhook_input_template && strcontains(jsondecode(local.webhook_input_template).text, "<type>")
    error_message = "the forwarder should get the same message as an API destination"
  }

  assert {
    condition     = length(aws_cloudwatch_event_api_destination.webhook) + length(aws_cloudwatch_event_connection.webhook) + length(aws_iam_role.webhook) == 0
    error_message = "no API destination, connection or role in GovCloud"
  }
}
