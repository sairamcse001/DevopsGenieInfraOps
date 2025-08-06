

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


# VPC and Networking

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "public_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
}

resource "aws_subnet" "public_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
}



data "aws_availability_zones" "available" {}

resource "aws_eip" "nat_eip" {
 vpc = true
}

resource "aws_nat_gateway" "nat" {
 allocation_id = aws_eip.nat_eip.id
 subnet_id     = aws_subnet.public_1.id

}


resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
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
    id = "auto_delete"
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
  bucket = "${local.app_name}-s3-logs"

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
  name = "${local.app_name}-dlq"
}


# Lambda Function

resource "aws_lambda_function" "example" {
 filename      = "lambda_function.zip" # Replace with your zip
 function_name = "${local.app_name}-lambda"
 handler       = "index.handler"
 runtime       = "nodejs16.x"
  memory_size = 128
  timeout = 300
  source_code_hash = filebase64sha256("lambda_function.zip")

 dead_letter_config {
    target_arn = aws_sqs_queue.dlq.arn
  }
}


resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name = "/aws/lambda/${aws_lambda_function.example.function_name}"
  retention_in_days = 30
}


resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.main.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.example.arn
    events              = ["s3:ObjectCreated:*"]
 filter_suffix = ".zip"

  }
}

resource "aws_s3_bucket_policy" "allow_lambda_trigger" {
  bucket = aws_s3_bucket.main.id
  policy = data.aws_iam_policy_document.allow_lambda_trigger.json
}


data "aws_iam_policy_document" "allow_lambda_trigger" {
  statement {
    actions = ["s3:PutObject", "s3:PutObjectAcl"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
 resources = [aws_s3_bucket.main.arn]
 condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
 values = [aws_lambda_function.example.arn]
    }
  }
}

# -------- outputs.tf --------

output "s3_bucket_arn" {
  value = aws_s3_bucket.main.arn
}

output "lambda_function_arn" {
  value = aws_lambda_function.example.arn
}

output "sqs_queue_url" {
  value = aws_sqs_queue.dlq.url
}

output "s3_bucket_logs_arn" {
  value = aws_s3_bucket.logs.arn
}

# -------- terraform.tfvars --------

app_name = "devops-genie-appname"