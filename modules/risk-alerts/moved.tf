# State moves for callers coming from the risk_alerts input of
# pelotech/terraform-aws-account-bootstrap (up to v0.3.x). They apply when the
# module call keeps the same name and only its source changes; otherwise see
# the README. The old webhook resources (API destinations) have no equivalent
# here and are replaced by the forwarder.

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
