

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

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.app_name}-vpc"
  }
}

resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

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

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "${var.app_name}-public-route-table"
  }
}

resource "aws_route_table_association" "public_subnet_association" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public_route_table.id
}




data "aws_availability_zones" "available" {}


resource "aws_s3_bucket" "main" {
  bucket = "${var.app_name}-s3-bucket"


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

}


resource "aws_lambda_function" "main" {
 filename      = "lambda.zip" # Placeholder, replace or use inline code
  function_name = "${var.app_name}-lambda"
  handler       = "index.handler" # Placeholder, replace with actual handler
  runtime       = "nodejs16.x" # Or other runtime
  role          = "arn:aws:iam::123456789012:role/lambda_basic_execution" # Placeholder role ARN.  Replace with proper IAM.

  s3_bucket = aws_s3_bucket.main.id
  s3_key    = "lambda.zip"


 dead_letter_config {
    target_arn = aws_sqs_queue.dlq.arn
  }

}


resource "aws_sqs_queue" "dlq" {
  name = "${var.app_name}-dlq"
}


resource "aws_cloudwatch_log_group" "lambda_log_group" {
 name = "/aws/lambda/${aws_lambda_function.main.function_name}"
  retention_in_days = 7
}



resource "aws_s3_bucket_notification" "lambda_trigger" {
  bucket = aws_s3_bucket.main.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.main.arn
    events              = ["s3:ObjectCreated:*"]

    filter_prefix = "uploads/" # Or any prefix you desire
  }
}

resource "aws_s3_bucket_policy" "lambda_trigger_policy" {
 bucket = aws_s3_bucket.main.id
  policy = jsonencode({
    Version = "2012-10-17"
 Statement = [
      {
        Sid       = "AllowLambdaToWriteLogs"
        Action    = "s3:PutObject"
        Effect    = "Allow"
 Principal = {
          Service = "logs.amazonaws.com"
        }
 Resource = [
 "${aws_s3_bucket.logs.arn}",
          "${aws_s3_bucket.logs.arn}/log/*"
 ]
 Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
 }
        }
      },
      {
 Sid    = "AllowLambdaToGetObject"
 Action = "s3:GetObject"
 Effect = "Allow"
 Principal = {
          AWS = aws_lambda_function.main.arn
        }
 Resource = [
 "${aws_s3_bucket.main.arn}",
          "${aws_s3_bucket.main.arn}/*"
        ]
      },

      {
        Sid    = "AllowLambdaToPutObject"
        Action = "s3:PutObject"
 Effect  = "Allow"
        Principal = {
          AWS = aws_lambda_function.main.arn
 }
        Resource = [
 "${aws_s3_bucket.main.arn}",
          "${aws_s3_bucket.main.arn}/*"
 ]
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

output "s3_logs_bucket_arn" {
 value = aws_s3_bucket.logs.arn
}

# -------- terraform.tfvars --------

app_name = "devops-genie"