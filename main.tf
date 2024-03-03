terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    archive = {
      source = "hashicorp/archive"
    }
  }

  required_version = ">= 1.3.7"
}

provider "aws" {
  region  = "us-west-2"
  profile = "job-listing-analyzer"

  default_tags {
    tags = {
      app = "job-listing-analyzer-terraform"
    }
  }
}

// zip the js code, as we can upload only zip files to AWS lambda
data "archive_file" "function_archive" {
  type        = "zip"
  source_dir  = "./src"
  output_path = "${path.module}/.terraform/archive_files/function.zip"

  depends_on = [null_resource.dependencies]
}

# Provisioner to install dependencies in lambda package before upload it.
resource "null_resource" "dependencies" {

  triggers = {
    updated_at = timestamp()
  }

  provisioner "local-exec" {
    command = <<EOF
    npm install
    EOF

    working_dir = "${path.module}/src"
  }
}


resource "aws_lambda_function" "job_analyzer_function" {
  function_name = "job-analyzer"
  description   = "Pulls job listing from RSS feeds each morning, uses LLMs to read them and decide which best match the candidate profile, and sends an email with the results"
  role          = aws_iam_role.lambda.arn
  handler       = "src/index.handler" // This should be filename.exportedFunction
  memory_size   = 128
  filename      = "${path.module}/.terraform/archive_files/function.zip" // This should point to a .zip file
  runtime       = "nodejs20.x"                                           // AWS Lambda currently supports Node.js 12.x and 14.x

  # # upload the function if the code hash is changed
  source_code_hash = data.archive_file.function_archive.output_base64sha256

  environment {
    variables = {
      OPENAI_API_KEY   = local.OPENAI_API_KEY
      SENDGRID_API_KEY = local.SENDGRID_API_KEY
      RECIPIENT        = local.RECIPIENT
      SENDER           = local.SENDER
      PROMPT           = local.PROMPT
      MODEL            = local.MODEL
    }
  }
}


resource "aws_cloudwatch_log_group" "job_analyzer_logs" {
  name              = "/aws/lambda/${aws_lambda_function.job_analyzer_function.function_name}"
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
  name               = "AssumeJobListingAnalyzerLambdaRole"
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
  name        = "AllowJobListingAnalyzerLambdaLoggingPolicy"
  description = "Policy for lambda cloudwatch logging"
  policy      = data.aws_iam_policy_document.allow_lambda_logging.json
}

// attach policy to out created lambda role
resource "aws_iam_role_policy_attachment" "lambda_logging_policy_attachment" {
  role       = aws_iam_role.lambda.id
  policy_arn = aws_iam_policy.function_logging_policy.arn
}

resource "aws_cloudwatch_event_rule" "every_morning" {
  name                = "job-listing-analyzer-trigger"
  description         = "Fires every morning at 8am Pacific"
  schedule_expression = "cron(0 16 ? * * *)"
}

resource "aws_cloudwatch_event_target" "run_lambda_every_morning" {
  rule      = aws_cloudwatch_event_rule.every_morning.name
  target_id = "job_analyzer_lambda"
  arn       = aws_lambda_function.job_analyzer_function.arn
}

resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.job_analyzer_function.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.every_morning.arn
}