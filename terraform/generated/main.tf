

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
  default     = "devops-genie-appname"
}

# -------- main.tf --------

# VPC and Networking

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "public_1" {
  cidr_block        = "10.0.1.0/24"
  vpc_id            = aws_vpc.main.id
  availability_zone = data.aws_availability_zones.available.names[0]
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
}


resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_1.id

  depends_on = [aws_internet_gateway.gw]
}

resource "aws_eip" "nat" {
  vpc = true
}




# S3 Buckets

resource "aws_s3_bucket" "main" {
  bucket = "${var.app_name}-s3-bucket"
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
    id      = "auto_delete"
    enabled = true

    expiration {
      days = 30
    }
  }

 logging {
    target_bucket = aws_s3_bucket.logs.id
    target_prefix = "log/"
  }
}



resource "aws_s3_bucket" "logs" {
  bucket = "${var.app_name}-s3-logs"

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
    id      = "auto_delete"
    enabled = true
    expiration {
      days = 30
    }
  }

}


# SQS Queue (DLQ)

resource "aws_sqs_queue" "dlq" {
  name = "${var.app_name}-dlq"
}


# Lambda Function

resource "aws_lambda_function" "example" {
  filename         = "lambda_function.zip" # Replace with actual zip or use 'runtime' and 'handler' for inline code.
  function_name    = "${var.app_name}-lambda"
  role             = aws_iam_role.lambda_exec.arn # IAM role is not defined here because it was explicitly excluded. But in a real setup you would need this
  handler          = "main" # Replace with actual handler if using inline code.
  source_code_hash = filebase64sha256("lambda_function.zip") # Replace with actual zip or use 'runtime' and 'handler' for inline code.
  runtime          = "python3.9" # Replace with actual runtime if using inline code.

  dead_letter_config {
    target_arn = aws_sqs_queue.dlq.arn
  }


}

resource "aws_s3_bucket_notification" "lambda_trigger" {
  bucket = aws_s3_bucket.main.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.example.arn
    events              = ["s3:ObjectCreated:*"]
  }
 depends_on = [aws_lambda_permission.allow_bucket_to_invoke_lambda]
}


# Lambda permission for S3 to invoke
resource "aws_lambda_permission" "allow_bucket_to_invoke_lambda" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.example.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.main.arn
}


# Example inline Lambda function (replace with your actual code)
data "archive_file" "lambda_zip" {
 type        = "zip"
 source_dir = "./lambda_src/" # Assumes you have a local directory with your Lambda code
 output_path = "lambda_function.zip"
}



data "aws_availability_zones" "available" {}
data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}


# IAM - PLACEHOLDER, replace with proper IAM definitions as required
resource "aws_iam_role" "lambda_exec" {
  name               = "devops-genie-appname-lambda-role"
 assume_role_policy = data.aws_iam_policy_document.assume_role.json

}


# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_log_group" {
 name = "/aws/lambda/${aws_lambda_function.example.function_name}"
 retention_in_days = 30
}

# -------- outputs.tf --------

output "s3_bucket_arn" {
  value = aws_s3_bucket.main.arn
}

output "lambda_function_arn" {
  value = aws_lambda_function.example.arn
}

output "dlq_url" {
  value = aws_sqs_queue.dlq.url
}

# -------- terraform.tfvars --------

app_name = "devops-genie-appname"