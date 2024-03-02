terraform {
    required_providers {
        aws = {
            source = "hashicorp/aws"
        }
    }
}

provider "aws" {
    region = "us-west-2"
    profile = "job-listing-analyzer"

    default_tags {
        tags = {
            app = "job-listing-analyzer-terraform"
        }
    }
}

resource "aws_lambda_function" "job_analyzer_funtion" {
    function_name = "job-analyzer"
    decription = "Pulls job listing from RSS feeds each morning, uses LLMs to read them and decide which best match the candidate profile, and sends an email with the results"
    role = aws_iam_role.lambda.arn
    handler = "lambda_handler"
    memory_size = 128
    filename = "./src/handler.js"
    runtime = "nodejs20.x"
}

resource "aws_cloudwatch_log_group" "job_analyzer_logs" {
    name = "aws/lambda/${aws_lambda_function.job_analyzer_funtion.function_name}"
    retention_in_days = 7
}

data "aws_iam_policy_document" "assume_lambda_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

// create lambda role, that lambda function can assume (use)
resource "aws_iam_role" "lambda" {
  name               = "AssumeLambdaRole"
  description        = "Role for lambda to assume lambda"
  assume_role_policy = data.aws_iam_policy_document.assume_lambda_role.json
}

data "aws_iam_policy_document" "allow_lambda_logging" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = [
      "arn:aws:logs:*:*:*",
    ]
  }
}

// create a policy to allow writing into logs and create logs stream
resource "aws_iam_policy" "function_logging_policy" {
  name        = "AllowLambdaLoggingPolicy"
  description = "Policy for lambda cloudwatch logging"
  policy      = data.aws_iam_policy_document.allow_lambda_logging.json
}

// attach policy to out created lambda role
resource "aws_iam_role_policy_attachment" "lambda_logging_policy_attachment" {
  role       = aws_iam_role.lambda.id
  policy_arn = aws_iam_policy.function_logging_policy.arn
}

resource "aws_cloudwatch_event_rule" "every_morning" {
  name                = "every-morning"
  description         = "Fires every morning at 8am Pacific"
  schedule_expression = "cron(0 16 ? * * *)"
}

resource "aws_cloudwatch_event_target" "run_lambda_every_morning" {
  rule      = aws_cloudwatch_event_rule.every_morning.name
  target_id = "job_analyzer_lambda"
  arn       = aws_lambda_function.job_analyzer_funtion.arn
}

resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.job_analyzer_funtion.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.every_morning.arn
}