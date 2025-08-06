

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

resource "aws_subnet" "public_1" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

}

resource "aws_subnet" "public_2" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]
}

resource "aws_internet_gateway" "gw" {
 vpc_id = aws_vpc.main.id
}


resource "aws_default_route_table" "main" {
 default_route {
   gateway_id = aws_internet_gateway.gw.id
   destination_cidr_block = "0.0.0.0/0"

 }
}

resource "aws_route_table_association" "a" {
 subnet_id      = aws_subnet.public_1.id
 route_table_id = aws_default_route_table.main.id
}
resource "aws_route_table_association" "b" {
 subnet_id      = aws_subnet.public_2.id
 route_table_id = aws_default_route_table.main.id
}

data "aws_availability_zones" "available" {}


# S3 Bucket (Main)
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
   id = "auto-delete-after-30-days"
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

# S3 Bucket (Logs)

resource "aws_s3_bucket" "logs" {
  bucket = "${var.app_name}-s3-logs"

}


# Lambda Function
resource "aws_lambda_function" "main" {
 filename         = "lambda_function.zip" # Replace with your actual lambda code
 function_name = "${var.app_name}-lambda"
 handler = "index.handler" # Adjust if needed
 runtime = "nodejs16.x" # Replace as appropriate

 s3_bucket = aws_s3_bucket.main.id
 s3_key    = "lambda_function.zip" # Replace as needed
}

# SQS Queue (DLQ)
resource "aws_sqs_queue" "dlq" {
 name = "${var.app_name}-dlq"
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda" {
 name = "/aws/lambda/${aws_lambda_function.main.function_name}"
 retention_in_days = 30
}

# S3 Bucket Notification
resource "aws_s3_bucket_notification" "lambda_trigger" {
 bucket = aws_s3_bucket.main.id

 lambda_function {
   lambda_function_arn = aws_lambda_function.main.arn
   events              = ["s3:ObjectCreated:*"]

 }
}

# -------- outputs.tf --------

output "s3_bucket_arn" {
 value = aws_s3_bucket.main.arn
}

output "lambda_function_arn" {
 value = aws_lambda_function.main.arn
}

output "sqs_queue_url" {
 value = aws_sqs_queue.dlq.url
}

# -------- terraform.tfvars --------

app_name = "devops-genie"