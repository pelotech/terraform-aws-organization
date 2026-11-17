# Sends AWS Health RISK events (for example exposed access keys) to an SNS
# topic with email subscriptions, and to chat webhooks (webhooks.tf). Applied
# in the organization's AWS Health delegated administrator or management
# account, the rule sees every account's events; anywhere else, only that
# account's.
#
# AWS Health sends events that aren't tied to a region, such as exposed keys,
# to us-east-1 (us-gov-west-1 in GovCloud), so everything is created there
# whatever region the provider uses.

data "aws_partition" "current" {}

locals {
  name   = "health-risk-alerts"
  region = data.aws_partition.current.partition == "aws-us-gov" ? "us-gov-west-1" : "us-east-1"
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
