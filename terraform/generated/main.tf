

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

resource "aws_eip" "nat_eip" {
  vpc = true
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_1.id
}




data "aws_availability_zones" "available" {}



# S3 Buckets

resource "aws_s3_bucket" "main" {
  bucket = "${var.app_name}-s3-bucket"


 lifecycle_rule {
    id      = "auto_delete"
    enabled = true

    expiration {
      days = 30
    }
  }

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

}


# Lambda Function and supporting resources

resource "aws_sqs_queue" "dlq" {
  name = "${var.app_name}-dlq"
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name = "/aws/lambda/${var.app_name}-lambda"
}

resource "aws_lambda_function" "example" {
  filename      = "lambda_function.zip" # Replace with your lambda zip file
  function_name = "${var.app_name}-lambda"
  role          = "arn:aws:iam::123456789012:role/lambda_basic_execution" # Replace with a real role ARN later. IAM is out of scope for now.
  handler       = "main.handler" # Update based on your lambda handler.
 source_code_hash = filebase64sha256("lambda_function.zip")
  runtime = "python3.9"  # Set to your lambda runtime

  dead_letter_config {
    target_arn = aws_sqs_queue.dlq.arn
  }


}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.main.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.example.arn
    events              = ["s3:ObjectCreated:*"]
  }
 depends_on = [aws_lambda_permission.allow_bucket]
}

resource "aws_lambda_permission" "allow_bucket" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.example.function_name
  principal     = "s3.amazonaws.com"
 source_arn    = aws_s3_bucket.main.arn
}

# -------- outputs.tf --------

output "s3_bucket_arn" {
  value = aws_s3_bucket.main.arn
}

output "lambda_function_arn" {
  value = aws_lambda_function.example.arn
}

output "s3_logs_bucket_arn" {
 value = aws_s3_bucket.logs.arn
}

output "dlq_arn" {
 value = aws_sqs_queue.dlq.arn
}

# -------- terraform.tfvars --------

app_name = "devops-genie-appname"