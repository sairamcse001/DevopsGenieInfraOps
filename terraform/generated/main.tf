

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

data "aws_availability_zones" "available" {}


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
    id      = "delete_old_objects"
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

  acl    = "log-delivery-write"
  force_destroy = true
}



# SQS Queue (DLQ)
resource "aws_sqs_queue" "dlq" {
  name = "${var.app_name}-dlq"
}

# Lambda Function
resource "aws_lambda_function" "main" {
 filename      = "lambda_function_payload.zip" # Replace with your zipped code
 function_name = "${var.app_name}-lambda"
 handler       = "main" # Replace with the appropriate handler
 runtime       = "python3.9" # Or other runtimes
 memory_size  = 128
 timeout       = 30

 s3_bucket = "your-s3-bucket-with-lambda-code"
 s3_key    = "lambda_function_payload.zip"


  dead_letter_config {
 target_arn = aws_sqs_queue.dlq.arn
  }
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda" {
  name = "/aws/lambda/${aws_lambda_function.main.function_name}"
  retention_in_days = 30
}


# S3 Bucket Notification to Lambda
resource "aws_s3_bucket_notification" "lambda_trigger" {
  bucket = aws_s3_bucket.main.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.main.arn
    events              = ["s3:ObjectCreated:*"]
   filter_suffix = ".zip" # Example filter

  }
}

# Bucket Policy
resource "aws_s3_bucket_policy" "allow_lambda_trigger" {
 bucket = aws_s3_bucket.main.id
 policy = data.aws_iam_policy_document.allow_lambda_trigger.json
}


data "aws_iam_policy_document" "allow_lambda_trigger" {
  statement {
    actions = ["s3:PutObject", "s3:GetObject", "s3:ListBucket"]
    principals {
 type = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    resources = [
 aws_s3_bucket.main.arn,
      "${aws_s3_bucket.main.arn}/*",
    ]

  }
  statement {
    actions = ["s3:GetBucketLocation"]
    principals {
 type = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    resources = [aws_s3_bucket.main.arn]

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

app_name = "devops-genie-appname"