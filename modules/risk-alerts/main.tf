# Sends AWS Health RISK events (for example exposed access keys) to an SNS
# topic with email subscriptions and to chat webhooks. Applied in the
# organization's AWS Health delegated administrator or management account, the
# rule sees every account's events; anywhere else, only that account's.
#
# AWS Health sends events that aren't tied to a region, such as exposed keys,
# to us-east-1 (us-gov-west-1 in GovCloud), so everything is created there
# whatever region the provider uses.

data "aws_partition" "current" {}

locals {
  name   = "health-risk-alerts"
  region = data.aws_partition.current.partition == "aws-us-gov" ? "us-gov-west-1" : "us-east-1"

  # Only the names: the URLs are secrets, and for_each keys show up in plans.
  webhooks = toset(nonsensitive(keys(var.webhook_urls)))

  # GovCloud has no EventBridge API destinations, so webhooks go through a
  # Lambda subscribed to the topic there (forwarder.tf).
  use_forwarder = data.aws_partition.current.partition == "aws-us-gov"
  api_webhooks  = local.use_forwarder ? toset([]) : local.webhooks
}

resource "aws_cloudwatch_event_rule" "this" {
  region      = local.region
  name        = local.name
  description = "AWS Health RISK events (e.g. exposed access keys) to the incident channel"
  event_pattern = jsonencode({
    source        = ["aws.health"]
    "detail-type" = ["AWS Health Event"]
    detail = {
      service = ["RISK"]
    }
  })
  tags = var.tags
}

# No server-side encryption: EventBridge can't publish through the AWS managed
# SNS key, and these messages carry event metadata, not secrets.
module "topic" {
  source  = "terraform-aws-modules/sns/aws"
  version = "7.1.0"

  region = local.region
  name   = local.name
  tags   = var.tags

  topic_policy_statements = {
    events = {
      sid     = "AllowHealthRiskRule"
      actions = ["sns:Publish"]
      principals = [{
        type        = "Service"
        identifiers = ["events.amazonaws.com"]
      }]
      condition = [{
        test     = "ArnEquals"
        variable = "aws:SourceArn"
        values   = [aws_cloudwatch_event_rule.this.arn]
      }]
    }
  }

  subscriptions = {
    for email in var.email_endpoints : email => {
      protocol = "email"
      endpoint = email
    }
  }
}

resource "aws_cloudwatch_event_target" "topic" {
  region = local.region
  rule   = aws_cloudwatch_event_rule.this.name
  arn    = module.topic.topic_arn
}

# Chat webhooks, where API destinations exist. Slack and Google Chat both
# accept {"text": "..."}, so one API destination per webhook covers either.
#
# An API destination needs a connection, and a connection needs some auth. The
# webhook URL is the real credential, so this header is only a placeholder.
resource "aws_cloudwatch_event_connection" "webhook" {
  count = length(local.api_webhooks) == 0 ? 0 : 1

  region             = local.region
  name               = local.name
  authorization_type = "API_KEY"

  auth_parameters {
    api_key {
      key   = "X-Source"
      value = local.name
    }
  }
}

resource "aws_cloudwatch_event_api_destination" "webhook" {
  for_each = local.api_webhooks

  region              = local.region
  name                = "${local.name}-${each.key}"
  connection_arn      = aws_cloudwatch_event_connection.webhook[0].arn
  invocation_endpoint = var.webhook_urls[each.key]
  http_method         = "POST"
}

resource "aws_iam_role" "webhook" {
  count = length(local.api_webhooks) == 0 ? 0 : 1

  name = local.name
  tags = var.tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "events.amazonaws.com" }
      Condition = { ArnEquals = { "aws:SourceArn" = aws_cloudwatch_event_rule.this.arn } }
    }]
  })
}

resource "aws_iam_role_policy" "webhook" {
  count = length(local.api_webhooks) == 0 ? 0 : 1

  name = "invoke-webhooks"
  role = aws_iam_role.webhook[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "events:InvokeApiDestination"
      Resource = [for name in local.api_webhooks : aws_cloudwatch_event_api_destination.webhook[name].arn]
    }]
  })
}

resource "aws_cloudwatch_event_target" "webhook" {
  for_each = local.api_webhooks

  region    = local.region
  rule      = aws_cloudwatch_event_rule.this.name
  target_id = "webhook-${each.key}"
  arn       = aws_cloudwatch_event_api_destination.webhook[each.key].arn
  role_arn  = aws_iam_role.webhook[0].arn

  input_transformer {
    input_paths = {
      type    = "$.detail.eventTypeCode"
      account = "$.detail.affectedAccount"
      region  = "$.detail.eventRegion"
    }
    # Written by hand: jsonencode would escape the <placeholders>.
    input_template = "{\"text\": \"AWS Health risk alert: <type> in account <account> (<region>). Open AWS Health in that account for details.\"}"
  }
}
