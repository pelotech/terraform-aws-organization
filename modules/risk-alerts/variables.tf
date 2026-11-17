variable "email_endpoints" {
  type        = set(string)
  default     = []
  description = "Addresses to notify. Each must confirm the subscription AWS emails it."
}

variable "webhook_urls" {
  type        = map(string)
  default     = {}
  description = "Name => incoming webhook URL: a Slack channel, a Google Chat space, or anything else that accepts a JSON body with a text field. The URLs are secrets and are stored in state; pass them from sensitive variables."

  validation {
    condition = alltrue([
      for name, url in var.webhook_urls : can(regex("^[A-Za-z0-9_-]+$", name)) && startswith(url, "https://")
    ])
    error_message = "webhook_urls names may use letters, digits, - and _, and each URL must start with https://."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to the resources this module creates."
}
