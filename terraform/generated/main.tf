

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
 region = "us-west-2" # Default AWS region
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
  tags = {
    Name = "${var.app_name}-vpc"
  }
}

resource "aws_subnet" "public_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
 tags = {
    Name = "${var.app_name}-public-subnet-1"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
 tags = {
    Name = "${var.app_name}-igw"
  }
}


resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_1.id
 tags = {
    Name = "${var.app_name}-nat"
  }
  depends_on = [aws_internet_gateway.gw]
}
resource "aws_eip" "nat" {
 vpc = true
 tags = {
    Name = "${var.app_name}-nat-eip"
  }

}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
 gateway_id = aws_internet_gateway.gw.id
  }

 tags = {
    Name = "${var.app_name}-public-route-table"
  }
}

resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

# S3 Bucket (Main)
resource "aws_s3_bucket" "main" {
  bucket = "${var.app_name}-s3-bucket"
  acl    = "private"


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
    id                                     = "auto-delete-rule"
    enabled                                = true
    expiration {
      days = 30
    }
  }


 logging {
    target_bucket = aws_s3_bucket.logs.id
    target_prefix = "log/"
  }
}



# S3 Bucket (Logs)
resource "aws_s3_bucket" "logs" {
  bucket = "${var.app_name}-s3-logs"
  acl    = "log-delivery-write"

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
    id                                     = "auto-delete-rule"
    enabled                                = true
    expiration {
      days = 30
    }
  }
}



# Lambda Function
resource "aws_lambda_function" "main" {

 filename      = "lambda_function.zip" # Placeholder
  function_name = "${var.app_name}-lambda"
  handler       = "index.handler" # Placeholder
  runtime        = "nodejs16.x"
  role          = "" # No IAM in this scenario
  memory_size   = 128
  timeout       = 30



 dead_letter_config {
    target_arn = aws_sqs_queue.dlq.arn
  }
}



# SQS Queue (DLQ)
resource "aws_sqs_queue" "dlq" {
  name = "${var.app_name}-dlq"
}



# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${aws_lambda_function.main.function_name}"
  retention_in_days = 30
}


# S3 Bucket Notification to Lambda
resource "aws_s3_bucket_notification" "lambda_trigger" {
  bucket = aws_s3_bucket.main.id

 lambda_function {
    lambda_function_arn = aws_lambda_function.main.arn
    events              = ["s3:ObjectCreated:*"]

    filter_prefix = "input/" # Example filter
  }

 depends_on = [aws_lambda_function.main]
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
output "s3_logs_bucket_arn" {
  value = aws_s3_bucket.logs.arn
}

# -------- terraform.tfvars --------

