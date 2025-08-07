

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
 region = "us-east-1"
}

# -------- variables.tf --------

variable "app_name" {
  type        = string
  description = "Name of the application"
  default     = "devops-genie"
}

# -------- main.tf --------

# VPC Resources
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
}

resource "aws_eip" "nat" {
 vpc = true
}

resource "aws_route_table" "public_route" {
  vpc_id = aws_vpc.main.id

 route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}


resource "aws_route_table_association" "public_subnet_assoc" {
 subnet_id      = aws_subnet.public_1.id
 route_table_id = aws_route_table.public_route.id
}



# S3 Buckets
resource "aws_s3_bucket" "video_storage" {
  bucket = "${var.app_name}-video-storage"

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
    id      = "auto_delete_after_30_days"
    enabled = true

 expiration {
      days = 30
    }
  }

 logging {
    target_bucket = aws_s3_bucket.log_bucket.id
 target_prefix = "video-storage-logs/"
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
}



# SQS Queue (DLQ)
resource "aws_sqs_queue" "lambda_dlq" {
  name = "${var.app_name}-lambda-dlq"
}

# Lambda Function
resource "aws_lambda_function" "video_processing" {
  filename      = "lambda_function.zip" # Replace with your zip file if needed. Can be empty.
  function_name = "${var.app_name}-video-processing"
  role          = "arn:aws:iam::123456789012:role/lambda_basic_execution" # Placeholder, IAM is excluded
  handler       = "main.handler" # Adjust as needed
  runtime       = "python3.9"    # Adjust as needed
  memory_size   = 128            # Adjust as needed.
 timeout       = 180            # Optional.

  dead_letter_config {
 target_arn = aws_sqs_queue.lambda_dlq.arn
  }
}



# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.video_processing.function_name}"
 retention_in_days = 30
}


# S3 Notification to trigger Lambda
resource "aws_s3_bucket_notification" "video_upload_notification" {
  bucket = aws_s3_bucket.video_storage.id

 lambda_function {
    lambda_function_arn = aws_lambda_function.video_processing.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "" #Optional
    filter_suffix       = "" #Optional
  }
}


# Dummy Lambda function zip file (if needed)
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "lambda_function.zip"
 source_dir = "./dummy-lambda" # Directory where the dummy file resides
}

# -------- outputs.tf --------

output "s3_bucket_video_storage_arn" {
  value = aws_s3_bucket.video_storage.arn
}

output "lambda_function_arn" {
  value = aws_lambda_function.video_processing.arn
}

output "sqs_queue_dlq_arn" {
  value = aws_sqs_queue.lambda_dlq.arn
}

output "s3_bucket_log_bucket_arn" {
 value = aws_s3_bucket.log_bucket.arn
}

output "vpc_id" {
 value = aws_vpc.main.id
}

output "nat_gateway_id" {
 value = aws_nat_gateway.nat.id
}

# -------- terraform.tfvars --------

app_name = "devops-genie"