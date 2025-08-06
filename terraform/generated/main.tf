

# -------- provider.tf --------

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
 region = "us-east-1"
}

# -------- variables.tf --------

variable "app_name" {
  type        = string
  description = "Name of the application"
  default     = "devops-genie"
}

# -------- main.tf --------

resource "aws_s3_bucket" "main_bucket" {
  bucket = "${var.app_name}-main-bucket"

  versioning {
    enabled = true
  }

 server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
 sse_algorithm     = "AES256"
      }
    }
  }

  lifecycle_rule {
    id      = "remove_old_files"
    enabled = true
    expiration {
      days = 30
    }
  }

 logging {
    target_bucket = aws_s3_bucket.log_bucket.id
 target_prefix = "log/"
  }
}


resource "aws_s3_bucket" "log_bucket" {
 bucket = "${var.app_name}-log-bucket"

 server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
 sse_algorithm     = "AES256"
      }
    }
  }

  lifecycle_rule {
    id      = "remove_old_logs"
    enabled = true

    expiration {
 days = 30
 }
  }
}

resource "aws_lambda_function" "processor_lambda" {
 filename         = "lambda_function.zip" # Placeholder, replace as needed
 function_name    = "${var.app_name}-processor-lambda"
 handler          = "index.handler" # Placeholder, replace as needed
 runtime          = "nodejs16.x"
 source_code_hash = filebase64sha256("lambda_function.zip")

  s3_bucket  = aws_s3_bucket.main_bucket.id
  s3_key    = "lambda_function.zip" # Example, replace as needed

}


resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.main_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.processor_lambda.arn
    events              = ["s3:ObjectCreated:*"]
 filter_prefix = ""
  }
}

resource "aws_sqs_queue" "dlq" {
  name = "${var.app_name}-dlq"
}

resource "aws_lambda_event_source_mapping" "example" {
  event_source_arn   = aws_s3_bucket.main_bucket.arn
  function_name      = aws_lambda_function.processor_lambda.arn
  enabled = true

  batch_size = 10
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name = "/aws/lambda/${aws_lambda_function.processor_lambda.function_name}"
  retention_in_days = 30
}

resource "aws_default_vpc" "default_vpc" {}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_default_vpc.default_vpc.id

  tags = {
    Name = "${var.app_name}-igw"
  }
}

# -------- outputs.tf --------

output "main_bucket_arn" {
 value = aws_s3_bucket.main_bucket.arn
}

output "lambda_function_arn" {
  value = aws_lambda_function.processor_lambda.arn
}

output "dlq_url" {
  value = aws_sqs_queue.dlq.url
}

# -------- terraform.tfvars --------

app_name = "devops-genie"