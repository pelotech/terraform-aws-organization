# Chat webhooks. The rule invokes one small Lambda with a {"text": "..."}
# message, and the Lambda posts it to each webhook URL. Slack, Google Chat and
# anything else that accepts that body work.
#
# A Lambda, not EventBridge API destinations, so that commercial and GovCloud
# (which has no API destinations) work the same way.

locals {
  forwarder_name = "${local.name}-forwarder"

  # nonsensitive: only whether there are any, not the URLs.
  forwarder_count = nonsensitive(length(var.webhook_urls)) > 0 ? 1 : 0
}

# A resource, not the data source: the data source builds the zip at plan
# time only, so a saved plan applied on another machine would not find it.
resource "archive_file" "forwarder" {
  count = local.forwarder_count

  type        = "zip"
  output_path = "${path.module}/forwarder.zip"

  source {
    content  = file("${path.module}/forwarder.mjs")
    filename = "index.mjs"
  }
}

resource "aws_cloudwatch_log_group" "forwarder" {
  count = local.forwarder_count

  region            = local.region
  name              = "/aws/lambda/${local.forwarder_name}"
  retention_in_days = 30
  tags              = var.tags
}

resource "aws_iam_role" "forwarder" {
  count = local.forwarder_count

  name = local.forwarder_name
  tags = var.tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "forwarder" {
  count = local.forwarder_count

  name = "write-logs"
  role = aws_iam_role.forwarder[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.forwarder[0].arn}:*"
    }]
  })
}

resource "aws_lambda_function" "forwarder" {
  count = local.forwarder_count

  region           = local.region
  function_name    = local.forwarder_name
  description      = "Posts AWS Health RISK alerts to chat webhooks"
  role             = aws_iam_role.forwarder[0].arn
  runtime          = "nodejs24.x"
  handler          = "index.handler"
  filename         = archive_file.forwarder[0].output_path
  source_code_hash = archive_file.forwarder[0].output_base64sha256
  # Webhooks are tried in turn with a 5 second timeout each.
  timeout = 60
  tags    = var.tags

  environment {
    variables = {
      WEBHOOK_URLS = sensitive(jsonencode(var.webhook_urls))
    }
  }

  depends_on = [aws_cloudwatch_log_group.forwarder, aws_iam_role_policy.forwarder]
}

resource "aws_lambda_permission" "forwarder" {
  count = local.forwarder_count

  region        = local.region
  statement_id  = "AllowHealthRiskRule"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.forwarder[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.this.arn
}

resource "aws_cloudwatch_event_target" "forwarder" {
  count = local.forwarder_count

  region    = local.region
  rule      = aws_cloudwatch_event_rule.this.name
  target_id = "webhooks"
  arn       = aws_lambda_function.forwarder[0].arn

  input_transformer {
    input_paths = {
      type    = "$.detail.eventTypeCode"
      account = "$.detail.affectedAccount"
      region  = "$.detail.eventRegion"
    }
    # Written by hand: jsonencode would escape the <placeholders>.
    input_template = "{\"text\": \"AWS Health risk alert: <type> in account <account> (<region>). Open AWS Health in that account for details.\"}"
  }

  depends_on = [aws_lambda_permission.forwarder]
}
