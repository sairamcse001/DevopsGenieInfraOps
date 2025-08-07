

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

locals {
  app_name = var.app_name
}


# VPC Resources
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "public_1" {
  cidr_block        = "10.0.1.0/24"
  vpc_id            = aws_vpc.main.id
  availability_zone = data.aws_availability_zones.available.names[0]
}

resource "aws_subnet" "public_2" {
  cidr_block        = "10.0.2.0/24"
  vpc_id            = aws_vpc.main.id
  availability_zone = data.aws_availability_zones.available.names[1]
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_eip" "nat_eip" {
 vpc = true
}

resource "aws_nat_gateway" "gw" {
 allocation_id = aws_eip.nat_eip.id
 subnet_id     = aws_subnet.public_1.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

 route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

resource "aws_route_table_association" "a" {
 subnet_id      = aws_subnet.public_1.id
 route_table_id = aws_route_table.public.id
}
resource "aws_route_table_association" "b" {
 subnet_id      = aws_subnet.public_2.id
 route_table_id = aws_route_table.public.id
}



# S3 Buckets
resource "aws_s3_bucket" "main" {
  bucket = "${local.app_name}-bucket"

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
    id      = "auto_delete_rule"
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
  bucket = "${local.app_name}-logs"

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
    id      = "auto_delete_rule"
    enabled = true


    expiration {
      days = 30
    }
  }


}

# SQS Queue (DLQ)
resource "aws_sqs_queue" "dlq" {
  name = "${local.app_name}-dlq"
}


# Lambda Function

data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "/tmp/lambda_function.zip"
  source_dir  = "./lambda_function"
}

resource "aws_lambda_function" "main" {

 filename         = data.archive_file.lambda_zip.output_path
  function_name = "${local.app_name}-lambda"
 handler       = "main.lambda_handler"

  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  runtime = "python3.9"

  dead_letter_config {
    target_arn = aws_sqs_queue.dlq.arn
  }
}


# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.main.function_name}"
  retention_in_days = 30
}

# S3 Bucket Notification to Lambda
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.main.id

 lambda_function {
    lambda_function_arn = aws_lambda_function.main.arn
 events              = ["s3:ObjectCreated:*"]

 filter_prefix = ""
 filter_suffix = ""

  }

}

# This is needed so lambda can access the S3 bucket
resource "aws_s3_bucket_policy" "allow_lambda_processing" {
  bucket = aws_s3_bucket.main.id

 policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid       = "AllowLambdaToProcess",
        Effect    = "Allow",
 Principal = {
          Service = "lambda.amazonaws.com"
        },
        Action = ["s3:GetObject", "s3:PutObject"],
        Resource = [
 "arn:aws:s3:::${aws_s3_bucket.main.id}/*",
          "arn:aws:s3:::${aws_s3_bucket.main.id}",
        ]
      },
    ]
  })


}

data "aws_availability_zones" "available" {}

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

output "s3_bucket_logs_arn" {
  value = aws_s3_bucket.logs.arn
}

# -------- terraform.tfvars --------

app_name = "devops-genie"