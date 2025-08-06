

# -------- provider.tf --------

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }

  required_version = ">= 1.2.0"
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
        sse_algorithm = "AES256"
      }
    }
  }

  lifecycle_rule {
    id      = "delete_old_objects"
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
        sse_algorithm = "AES256"
      }
    }
  }

  lifecycle_rule {
    id      = "delete_old_logs"
    enabled = true

    expiration {
      days = 30
    }
  }


}

resource "aws_lambda_function" "main_lambda" {
  filename         = "lambda_function.zip" # Replace with your lambda zip file
  function_name = "${var.app_name}-lambda"
  role            = aws_iam_role.lambda_role.arn # Requires IAM - Excluded in this specific example
  handler         = "index.handler" # Replace with your lambda handler
  runtime         = "nodejs16.x"

  s3_bucket = aws_s3_bucket.main_bucket.id
  s3_key    = "lambda_function.zip"
 source_code_hash = filebase64sha256("lambda_function.zip")



}


resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.main_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.main_lambda.arn
    events              = ["s3:ObjectCreated:*"]

  }
}

data "archive_file" "lambda_zip" {
    type        = "zip"
    output_path = "lambda_function.zip"
    source_dir  = "./lambda_code" # Folder with your lambda code
  }

resource "aws_sqs_queue" "dlq" {
  name = "${var.app_name}-dlq"
}

# -------- outputs.tf --------

output "main_bucket_arn" {
  value = aws_s3_bucket.main_bucket.arn
}

output "lambda_function_arn" {
  value = aws_lambda_function.main_lambda.arn
}

output "dlq_url" {
  value = aws_sqs_queue.dlq.url
}

# -------- terraform.tfvars --------

app_name = "devops-genie"