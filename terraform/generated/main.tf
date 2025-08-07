

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

# VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true
}


resource "aws_eip" "nat_eip" {
 vpc = true
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_1.id

  depends_on = [aws_internet_gateway.gw]

}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block        = "0.0.0.0/0"
 gateway_id = aws_internet_gateway.gw.id
  }

}

resource "aws_route_table_association" "public_subnet_1_association" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "public_subnet_2_association" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public_route_table.id
}


data "aws_availability_zones" "available" {}



# S3 Bucket (Main)
resource "aws_s3_bucket" "main" {
  bucket = "${var.app_name}-s3-main"

 lifecycle {
    ignore_changes = [tags]
 }
}

resource "aws_s3_bucket_versioning" "main" {
  bucket = aws_s3_bucket.main.id
  versioning_configuration {
    status = "Enabled"
  }
}


resource "aws_s3_bucket_server_side_encryption_configuration" "main" {
  bucket = aws_s3_bucket.main.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "AES256"
    }
  }
}



# S3 Bucket (Logging)
resource "aws_s3_bucket" "logging" {
 bucket = "${var.app_name}-s3-logging"

  lifecycle {
 ignore_changes = [tags]
 }

}


resource "aws_s3_bucket_logging" "main" {
 target_bucket = aws_s3_bucket.logging.id
  target_prefix = "log/"
  bucket        = aws_s3_bucket.main.id
}


resource "aws_s3_bucket_lifecycle_configuration" "main" {
  bucket = aws_s3_bucket.main.bucket

  rule {
    id     = "log-lifecycle-rule"
    status = "Enabled"

    expiration {
      days = 30
 }
  }
}


# Lambda Function
resource "aws_lambda_function" "main" {
 filename         = "lambda.zip" # Placeholder
  function_name = "${var.app_name}-lambda"
  handler       = "index.handler" # Placeholder
  runtime       = "nodejs16.x"
 source_code_hash = filebase64sha256("lambda.zip")

}



resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${aws_lambda_function.main.function_name}"
  retention_in_days = 30
}


# SQS Queue (DLQ)
resource "aws_sqs_queue" "dlq" {
  name                      = "${var.app_name}-sqs-dlq"
  message_retention_seconds = 86400 # 1 day
}


# Lambda Trigger (S3 → Lambda)
resource "aws_s3_bucket_notification" "lambda_trigger" {
 bucket = aws_s3_bucket.main.id

 lambda_function {
    lambda_function_arn = aws_lambda_function.main.arn
 events              = ["s3:ObjectCreated:*"]
    filter_prefix = ""
    filter_suffix = ""
 }
}

resource "aws_lambda_permission" "allow_s3_invoke" {
 statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
 function_name = aws_lambda_function.main.function_name
 principal     = "s3.amazonaws.com"
  source_arn   = aws_s3_bucket.main.arn
}

# -------- outputs.tf --------

output "s3_bucket_main_arn" {
  value = aws_s3_bucket.main.arn
}

output "lambda_function_arn" {
  value = aws_lambda_function.main.arn
}

output "sqs_queue_dlq_url" {
  value = aws_sqs_queue.dlq.url
}

output "s3_bucket_logging_arn" {
  value       = aws_s3_bucket_logging.main.target_bucket
}

# -------- terraform.tfvars --------

app_name = "devops-genie"