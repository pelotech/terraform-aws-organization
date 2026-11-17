# risk-alerts

AWS Health raises a RISK event when it finds a problem such as an access key exposed in a public repository. This module sends those events to the incident channel. It creates, all in one account:

- an EventBridge rule that matches AWS Health events whose service is `RISK`;
- an SNS topic that only that rule can publish to, built with [`terraform-aws-modules/sns`](https://registry.terraform.io/modules/terraform-aws-modules/sns/aws), with an email subscription for each address in `email_endpoints`;
- for each entry in `webhook_urls`, a one-line message posted to that webhook: through an EventBridge API destination, or in GovCloud, which has none, through one small Lambda that the rule invokes.

Both inputs are optional, so each team sets only what it uses.

```hcl
module "risk_alerts" {
  source = "git::https://github.com/pelotech/terraform-aws-organization.git//modules/risk-alerts?ref=vX.Y.Z"

  email_endpoints = ["incidents@example.com"]
  webhook_urls = {
    secops-chat  = var.chat_webhook_url  # Google Chat space
    secops-slack = var.slack_webhook_url # Slack channel
  }
}
```

## Where to apply it

The code is the same everywhere; the account you apply it in decides what it covers. Apply it in one account per organization, because applying it in more than one can send the same alert twice.

| Setup | Apply it in | Covers | Setup steps |
| ----- | ----------- | ------ | ----------- |
| Organization, with a delegated administrator (AWS's recommendation) | The delegated administrator, for example a security account | Every account, including ones added later | 1 and 2 below |
| Organization, without a delegated administrator | The management account | Every account, including ones added later | 1 below |
| No organization, or one account only | That account | That account | None |

A delegated administrator keeps the alerting out of the management account. Skip it if the organization has no separate security or operations account.

1. **Turn on organizational view**, once, signed in to the management account. In the [AWS Health Dashboard](https://health.aws.amazon.com/health/home), go to **Your organization health** > **Configurations** and choose **Enable organizational view**. The organization must have all features enabled. If the organization is managed with this repository's root module, `health.amazonaws.com` must also be in its `trusted_services`, since that list is authoritative.
2. **Register the delegated administrator**, once, from the management account. Either run the command below, or manage it in Terraform as [`examples/risk-alerts`](../../examples/risk-alerts) does.

   ```bash
   aws organizations register-delegated-administrator \
     --account-id <security-account-id> --service-principal health.amazonaws.com
   ```

If a step is missed, the module still applies cleanly and alerts for its own account only. To check, open **Your organization health** in the Health Dashboard of the account you applied to; it should list other accounts' events. AWS's guide is [Aggregating AWS Health events](https://docs.aws.amazon.com/health/latest/ug/aggregate-events.html).

## Details

- **Region.** Everything is created in `us-east-1` (`us-gov-west-1` in GovCloud), whatever region the provider uses. That is where AWS Health sends events that aren't tied to a region, such as exposed IAM access keys. A RISK event tied to another region is not picked up.
- **Email.** Each address has to confirm the subscription AWS emails it. The email is the raw event JSON: look at `detail.eventTypeCode`, `detail.affectedAccount` and `detail.affectedEntities`. For other destinations, subscribe to the `topic_arn` output.
- **Webhooks.** Create an incoming webhook in the [Slack channel](https://api.slack.com/messaging/webhooks) or [Google Chat space](https://developers.google.com/workspace/chat/quickstart/webhooks) and pass its URL. The body is plain JSON with a single `text` field and no Slack-specific formatting, so anything else that accepts `{"text": "..."}` works too. The message reads: `AWS Health risk alert: AWS_RISK_CREDENTIALS_EXPOSED in account 111111111111 (us-east-1). Open AWS Health in that account for details.`
- **GovCloud uses a Lambda.** GovCloud doesn't offer EventBridge API destinations, so there the rule invokes one Lambda (`health-risk-alerts-forwarder`) that posts the same message to every webhook. The inputs are the same in both partitions.
  - If a webhook rejects the message, the invocation fails. That shows in the function's error metric and log group, and AWS retries it twice, so the webhooks that did accept it can get the alert up to three times.
  - The Lambda's zip is built on the machine that runs Terraform, at plan and at apply, so nothing needs to be committed or uploaded separately.
- **Webhook URLs are secrets.** Anyone who has one can post to the channel. Pass them from sensitive variables. They are stored in Terraform state and are visible to anyone who can read EventBridge API destinations in the account (in GovCloud, the Lambda's environment variables).
- **Encryption.** The topic isn't encrypted at rest. EventBridge can't publish through the AWS managed SNS key, and the messages carry event metadata, not secrets.
- **Testing.** A real RISK event can't be triggered on demand, so test the two ends: publish a message to the topic, and `curl` a `{"text": "test"}` body to each webhook URL.

## Moving from `terraform-aws-account-bootstrap`

This module replaces the `risk_alerts` input of [`pelotech/terraform-aws-account-bootstrap`](https://github.com/pelotech/terraform-aws-account-bootstrap) (up to `v0.3.x`). Nothing is recreated if state is moved.

- **The module call only set `risk_alerts`:** keep the call's name, change its `source` to this module and lift `email_endpoints` and `webhook_urls` to the top level. The `moved` blocks in [`moved.tf`](moved.tf) do the rest. The plan must show moves only.
- **The module call also set other inputs** (`github`, `state_bucket`, ...): remove `risk_alerts` from that call, add a new call to this module and, in your root, one `moved` block per resource from the old call to the new one, for example:

  ```hcl
  moved {
    from = module.secops.aws_cloudwatch_event_rule.risk_alerts[0]
    to   = module.risk_alerts.aws_cloudwatch_event_rule.this
  }
  ```

  The full list of old and new addresses is in [`moved.tf`](moved.tf).

The output is now `topic_arn` (was `risk_alerts_topic_arn`).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0 |
| <a name="requirement_archive"></a> [archive](#requirement\_archive) | >= 2.8 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_archive"></a> [archive](#provider\_archive) | >= 2.8 |
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.0 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_topic"></a> [topic](#module\_topic) | terraform-aws-modules/sns/aws | 7.1.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [archive_file.forwarder](https://registry.terraform.io/providers/hashicorp/archive/latest/docs/resources/file) | resource |
| [aws_cloudwatch_event_api_destination.webhook](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_api_destination) | resource |
| [aws_cloudwatch_event_connection.webhook](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_connection) | resource |
| [aws_cloudwatch_event_rule.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_rule) | resource |
| [aws_cloudwatch_event_target.forwarder](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_target) | resource |
| [aws_cloudwatch_event_target.topic](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_target) | resource |
| [aws_cloudwatch_event_target.webhook](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_target) | resource |
| [aws_cloudwatch_log_group.forwarder](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_iam_role.forwarder](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.webhook](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.forwarder](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.webhook](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_lambda_function.forwarder](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function) | resource |
| [aws_lambda_permission.forwarder](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_permission) | resource |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_email_endpoints"></a> [email\_endpoints](#input\_email\_endpoints) | Addresses to notify. Each must confirm the subscription AWS emails it. | `set(string)` | `[]` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to the resources this module creates. | `map(string)` | `{}` | no |
| <a name="input_webhook_urls"></a> [webhook\_urls](#input\_webhook\_urls) | Name => incoming webhook URL: a Slack channel, a Google Chat space, or anything else that accepts a JSON body with a text field. The URLs are secrets and are stored in state; pass them from sensitive variables. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_topic_arn"></a> [topic\_arn](#output\_topic\_arn) | ARN of the SNS topic that receives AWS Health RISK events. Subscribe other destinations to it in your own root. |
<!-- END_TF_DOCS -->
