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
  # The Lambda and the event targets validate their ARNs.
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::222222222222:role/mock"
    }
  }
  mock_resource "aws_lambda_function" {
    defaults = {
      arn = "arn:aws:lambda:us-east-1:222222222222:function:health-risk-alerts-forwarder"
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
    condition     = length(aws_lambda_function.forwarder) + length(aws_iam_role.forwarder) + length(aws_cloudwatch_event_target.forwarder) == 0
    error_message = "no webhook_urls should create no forwarder"
  }
}

run "webhooks_go_through_the_forwarder" {
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
    condition     = length(aws_lambda_function.forwarder) == 1 && aws_lambda_function.forwarder[0].region == "us-east-1"
    error_message = "all webhooks share one Lambda, in the region AWS Health sends events to"
  }

  assert {
    condition     = toset(keys(jsondecode(nonsensitive(aws_lambda_function.forwarder[0].environment[0].variables.WEBHOOK_URLS)))) == toset(["secops-chat", "secops-slack"])
    error_message = "the forwarder should be given every webhook"
  }

  assert {
    condition     = strcontains(jsondecode(aws_cloudwatch_event_target.forwarder[0].input_transformer[0].input_template).text, "<type>")
    error_message = "the forwarder should be sent JSON with a text field holding unescaped placeholders"
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

run "govcloud_uses_its_own_region" {
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
    webhook_urls = {
      secops-slack = sensitive("https://hooks.slack.com/services/T000/B000/XXXX")
    }
  }

  assert {
    condition     = aws_cloudwatch_event_rule.this.region == "us-gov-west-1" && aws_cloudwatch_event_target.topic.region == "us-gov-west-1"
    error_message = "GovCloud rule and target should be in us-gov-west-1"
  }

  assert {
    condition     = length(aws_lambda_function.forwarder) == 1 && aws_lambda_function.forwarder[0].region == "us-gov-west-1"
    error_message = "GovCloud webhooks should use the same forwarder, in us-gov-west-1"
  }
}
