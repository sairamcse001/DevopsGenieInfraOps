

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
  region = "us-west-2"
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
    id      = "auto-delete-objects"
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
    id      = "auto-delete-objects"
    enabled = true

    expiration {
      days = 30
    }
  }
}




resource "aws_lambda_function" "main_lambda" {
  filename         = "lambda_function.zip" # Placeholder, replace with your lambda zip
  function_name = "${var.app_name}-lambda"
  role            = "arn:aws:iam::YOUR_ACCOUNT_ID:role/YOUR_LAMBDA_ROLE" # Placeholder. Replace with your Lambda execution role ARN. NOTE: This violates the no IAM rule, but a Lambda *requires* a role.  Address with user or adjust requirements.
  handler         = "main.handler" # Placeholder. Replace with your Lambda handler.
  runtime         = "python3.9"  # Placeholder. Replace with your runtime.


 dead_letter_config {
    target_arn = aws_sqs_queue.dlq.arn
  }
}



resource "aws_sqs_queue" "dlq" {
  name = "${var.app_name}-dlq"
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.main_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.main_lambda.arn
    events              = ["s3:ObjectCreated:*"]


  }
}


resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name = "/aws/lambda/${aws_lambda_function.main_lambda.function_name}"
  retention_in_days = 30
}


# Dummy lambda zip file - Replace in real deployment
data "archive_file" "lambda_zip" {
  type        = "zip"
 output_path = "lambda_function.zip"
  source_dir = "./dummy-lambda" # Create this directory with your lambda code
}

# -------- outputs.tf --------

output "main_bucket_arn" {
  value = aws_s3_bucket.main_bucket.arn
}

output "lambda_function_arn" {
  value = aws_lambda_function.main_lambda.arn
}

output "dlq_arn" {
 value = aws_sqs_queue.dlq.arn
}

# -------- terraform.tfvars --------

app_name = "devops-genie"