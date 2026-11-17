# Webhooks where API destinations don't exist (GovCloud): a small Lambda
# subscribed to the topic posts the same {"text": "..."} message to each
# webhook URL.

locals {
  forwarder_name  = "${local.name}-forwarder"
  forwarder_count = local.use_forwarder && length(local.webhooks) > 0 ? 1 : 0
}

data "archive_file" "forwarder" {
  count = local.forwarder_count

  type        = "zip"
  output_path = "${path.module}/forwarder.zip"

  source {
    content  = file("${path.module}/forwarder.py")
    filename = "index.py"
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
  description      = "Posts AWS Health RISK events from SNS to chat webhooks"
  role             = aws_iam_role.forwarder[0].arn
  runtime          = "python3.13"
  handler          = "index.handler"
  filename         = data.archive_file.forwarder[0].output_path
  source_code_hash = data.archive_file.forwarder[0].output_base64sha256
  timeout          = 30
  tags             = var.tags

  environment {
    variables = {
      WEBHOOK_URLS = jsonencode(var.webhook_urls)
    }
  }

  depends_on = [aws_cloudwatch_log_group.forwarder, aws_iam_role_policy.forwarder]
}

resource "aws_lambda_permission" "forwarder" {
  count = local.forwarder_count

  region        = local.region
  statement_id  = "AllowHealthRiskTopic"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.forwarder[0].function_name
  principal     = "sns.amazonaws.com"
  source_arn    = module.topic.topic_arn
}

resource "aws_sns_topic_subscription" "forwarder" {
  count = local.forwarder_count

  region    = local.region
  topic_arn = module.topic.topic_arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.forwarder[0].arn

  depends_on = [aws_lambda_permission.forwarder]
}
