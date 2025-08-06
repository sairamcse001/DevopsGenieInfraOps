

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
  default     = "devops-genie"
}

# -------- main.tf --------

# VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "public_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
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

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

resource "aws_route_table_association" "public_subnet_association" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}


# S3 Buckets
resource "aws_s3_bucket" "main" {
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
    id      = "expire_objects"
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
    id      = "expire_objects"
    enabled = true

    expiration {
      days = 30
    }
  }
}


# Lambda Function
resource "aws_lambda_function" "main" {
  function_name = "${var.app_name}-lambda"
  handler       = "index.handler" # Placeholder
  runtime       = "nodejs16.x"
  memory_size   = 128
  timeout       = 30

  # Replace with actual zip file or inline code
  filename      = "lambda_function_payload.zip" 
  source_code_hash = filebase64sha256("lambda_function_payload.zip")


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
  name = "/aws/lambda/${aws_lambda_function.main.function_name}"
  retention_in_days = 30
}

# S3 Notification to Lambda
resource "aws_s3_bucket_notification" "main_notification" {
  bucket = aws_s3_bucket.main.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.main.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix = "input/"
  }
}

resource "aws_s3_bucket_policy" "allow_lambda_trigger" {
  bucket = aws_s3_bucket.main.id
 policy = jsonencode({
    Version = "2012-10-17",
    Id = "Policy1694853728730",
    Statement = [
      {
        Sid = "Stmt1694853719207",
        Action = [
 "s3:GetBucketNotification",
 "s3:PutObject",
 "s3:PutObjectAcl",
 "s3:GetObject",
 "s3:GetObjectAcl",
 "s3:ListBucket",
          "s3:GetBucketLocation"
        ],
        Effect = "Allow",
        Resource = [
 aws_s3_bucket.main.arn,
 "${aws_s3_bucket.main.arn}/*"
        ],
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# -------- outputs.tf --------

output "s3_bucket_main_arn" {
  value = aws_s3_bucket.main.arn
}

output "lambda_function_arn" {
  value = aws_lambda_function.main.arn
}

output "sqs_queue_dlq_arn" {
  value = aws_sqs_queue.dlq.arn
}

output "s3_bucket_logs_arn" {
 value = aws_s3_bucket.logs.arn
}

# -------- terraform.tfvars --------

app_name = "devops-genie"