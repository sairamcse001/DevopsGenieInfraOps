

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

locals {
  app_name = var.app_name
}


resource "aws_s3_bucket" "main_bucket" {
  bucket = "${local.app_name}-main-bucket"
  versioning {
    enabled = true
  }

 server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

 lifecycle_rule {
    id      = "remove-old-files"
    enabled = true
    expiration {
      days = 30
    }
 }
}

resource "aws_s3_bucket" "log_bucket" {
  bucket = "${local.app_name}-log-bucket"
  acl    = "log-delivery-write"

 server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }


  logging {
    target_bucket = aws_s3_bucket.log_bucket.id
    target_prefix = "log/"
  }
}




resource "aws_s3_bucket_logging" "main_bucket_logging" {
  bucket        = aws_s3_bucket.main_bucket.id
 target_bucket = aws_s3_bucket.log_bucket.id
  target_prefix = "log/"
}


resource "aws_sqs_queue" "dlq" {
  name                      = "${local.app_name}-dlq"
  delay_seconds             = 0
  max_message_size         = 262144
  message_retention_seconds = 1209600
  receive_wait_time_seconds = 0
  visibility_timeout_seconds = 30
}



resource "aws_lambda_function" "processor_lambda" {
  filename      = "lambda_function.zip" # Placeholder. Replace with your zip or inline function
  function_name = "${local.app_name}-lambda"
  role          = "arn:aws:iam::123456789012:role/lambda_basic_execution" # Replace with actual ARN
  handler       = "main.handler"
  runtime = "python3.9" # adjust as needed
  s3_bucket = "your-bucket-name" # change to your bucket
  s3_key    = "lambda_function.zip" # your lambda zip file name


  dead_letter_config {
    target_arn = aws_sqs_queue.dlq.arn
  }

}


resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.main_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.processor_lambda.arn
    events              = ["s3:ObjectCreated:*"]
 filter_prefix = "inbound/" # Trigger lambda only for objects created under 'inbound/' prefix
  }

 depends_on = [aws_lambda_permission.allow_bucket_to_invoke_lambda]
}




resource "aws_lambda_permission" "allow_bucket_to_invoke_lambda" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.processor_lambda.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.main_bucket.arn
}


resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name = "/aws/lambda/${aws_lambda_function.processor_lambda.function_name}"
 retention_in_days = 30
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

output "log_bucket_arn" {
 value = aws_s3_bucket.log_bucket.arn
}

# -------- terraform.tfvars --------

app_name = "devops-genie"