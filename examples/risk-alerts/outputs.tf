output "topic_arn" {
  value       = module.risk_alerts.topic_arn
  description = "Topic to subscribe other destinations to."
}
