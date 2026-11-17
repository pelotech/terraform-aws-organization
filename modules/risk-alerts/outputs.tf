output "topic_arn" {
  value       = module.topic.topic_arn
  description = "ARN of the SNS topic that receives AWS Health RISK events. Subscribe other destinations to it in your own root."
}
