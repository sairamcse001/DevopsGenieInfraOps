

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
}

resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
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
    id      = "auto-delete-objects"
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
}

# SQS Queue (DLQ)
resource "aws_sqs_queue" "dlq" {
  name = "${var.app_name}-dlq"
}


# Lambda Function
resource "aws_lambda_function" "processor" {
 filename         = "lambda_function.zip" # Replace with your actual zip file or make it inline
 function_name    = "${var.app_name}-lambda"
 handler          = "main" # Your lambda handler
 source_code_hash = filebase64sha256("lambda_function.zip") # Replace with inline if needed
 runtime          = "python3.9"
 memory_size      = 128
 timeout          = 30

 dead_letter_config {
    target_arn = aws_sqs_queue.dlq.arn
  }
}




# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name = "/aws/lambda/${aws_lambda_function.processor.function_name}"
  retention_in_days = 30
}



# S3 Bucket Notification to trigger Lambda
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.main.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.processor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix = "uploads/"
  }

}

# Data sources
data "aws_availability_zones" "available" {}

# -------- outputs.tf --------

output "s3_bucket_arn" {
 value = aws_s3_bucket.main.arn
}

output "lambda_function_arn" {
  value = aws_lambda_function.processor.arn
}

output "sqs_queue_url" {
  value = aws_sqs_queue.dlq.url
}


output "s3_bucket_name" {
 value = aws_s3_bucket.main.bucket
}

# -------- terraform.tfvars --------

app_name = "devops-genie-appname"