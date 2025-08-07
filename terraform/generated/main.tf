

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
  default     = "devops-genie-appname"
}

# -------- main.tf --------

locals {
  app_name = var.app_name
}

# VPC Resources
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
}


resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_1.id
}


resource "aws_eip" "nat" {
  vpc = true
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}


resource "aws_route_table_association" "public_subnet_association" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public_route_table.id

}

# S3 Buckets
resource "aws_s3_bucket" "main" {
  bucket = "${local.app_name}-s3-bucket"
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
    id                                     = "remove_old_files"
    enabled                               = true
    expiration {
      days = 30
    }
    prefix = ""
  }

  logging {
    target_bucket = aws_s3_bucket.logging.id
    target_prefix = "log/"
  }

}




resource "aws_s3_bucket" "logging" {
  bucket = "${local.app_name}-s3-logging-bucket"

 server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

 lifecycle_rule {
    id                                     = "remove_old_logs"
    enabled                               = true
    expiration {
      days = 30
    }
    prefix = ""
  }



}



# Lambda Function (Example - replace with actual function)
resource "aws_lambda_function" "main" {
  filename         = "lambda_function.zip" # Or use "function_name" for inline
  function_name    = "${local.app_name}-lambda"
  handler          = "index.handler" # Replace with your handler
  source_code_hash = filebase64sha256("lambda_function.zip") # Or use inline code
  runtime          = "nodejs16.x" # Replace with your runtime
  role             = "arn:aws:iam::123456789012:role/devops-genie-appname-lambda-role" # REPLACE with actual IAM role.  This role will need to be created manually or in a separate module
  memory_size      = 128

 dead_letter_config {
    target_arn = aws_sqs_queue.dlq.arn
  }

}



# SQS Queue (DLQ)
resource "aws_sqs_queue" "dlq" {
  name = "${local.app_name}-dlq"
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.main.function_name}"
  retention_in_days = 30
}



data "aws_availability_zones" "available" {}



# S3 Bucket Notification to trigger Lambda
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.main.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.main.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix = ""
    filter_suffix = ""
 }
}



resource "aws_s3_bucket_policy" "allow_lambda_trigger" {
 bucket = aws_s3_bucket.main.id
 policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "AllowLambdaTrigger",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
        Action = "s3:PutObject",
        Resource = "arn:aws:s3:::${aws_s3_bucket.main.id}/*",
        Condition = {
          StringEquals = {
 "aws:SourceAccount" = "123456789012" # REPLACE with actual account ID
          },
 ArnLike = {
 "aws:SourceArn" = "${aws_lambda_function.main.arn}"
          }
        }
      },
 {
        Sid    = "AllowLambdaToGetBucketLocation",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
        Action = "s3:GetBucketLocation",
        Resource = "arn:aws:s3:::${aws_s3_bucket.main.id}",
        Condition = {
          StringEquals = {
 "aws:SourceAccount" = "123456789012" # REPLACE with actual account ID
          },
          ArnLike = {
 "aws:SourceArn" = "${aws_lambda_function.main.arn}"
          }
        }
      }
 ]
  })

}

# -------- outputs.tf --------

output "s3_bucket_arn" {
  value = aws_s3_bucket.main.arn
}

output "lambda_function_arn" {
  value = aws_lambda_function.main.arn
}

output "sqs_dlq_arn" {
 value = aws_sqs_queue.dlq.arn
}

output "s3_logging_bucket_arn" {
 value = aws_s3_bucket.logging.arn
}

# -------- terraform.tfvars --------

app_name = "devops-genie-appname"