# State moves for callers coming from the risk_alerts input of
# pelotech/terraform-aws-account-bootstrap (up to v0.3.x). They apply when the
# module call keeps the same name and only its source changes; otherwise see
# the README.

moved {
  from = aws_cloudwatch_event_rule.risk_alerts[0]
  to   = aws_cloudwatch_event_rule.this
}

moved {
  from = module.risk_alerts_topic[0]
  to   = module.topic
}

moved {
  from = aws_cloudwatch_event_target.risk_alerts_topic[0]
  to   = aws_cloudwatch_event_target.topic
}

moved {
  from = aws_cloudwatch_event_connection.risk_alerts_webhook
  to   = aws_cloudwatch_event_connection.webhook
}

moved {
  from = aws_cloudwatch_event_api_destination.risk_alerts_webhook
  to   = aws_cloudwatch_event_api_destination.webhook
}

moved {
  from = aws_iam_role.risk_alerts_webhook
  to   = aws_iam_role.webhook
}

moved {
  from = aws_iam_role_policy.risk_alerts_webhook
  to   = aws_iam_role_policy.webhook
}

moved {
  from = aws_cloudwatch_event_target.risk_alerts_webhook
  to   = aws_cloudwatch_event_target.webhook
}
