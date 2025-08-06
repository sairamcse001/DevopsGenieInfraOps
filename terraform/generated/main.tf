

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
 region = "us-west-2" # Default region
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



# S3 Buckets

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
    prefix  = ""
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


  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
 sse_algorithm     = "AES256"
      }
    }
  }


}



# Lambda Function and Related Resources
resource "aws_lambda_function" "main" {
  filename      = "lambda_function.zip" # Placeholder, replace with actual zip file
  function_name = "${var.app_name}-lambda"
  handler       = "main.handler" # Replace with actual handler
  runtime = "python3.9"

  source_code_hash = filebase64sha256("lambda_function.zip")

}



resource "aws_cloudwatch_log_group" "lambda" {
  name = "/aws/lambda/${aws_lambda_function.main.function_name}"
  retention_in_days = 30
}


resource "aws_sqs_queue" "dlq" {
  name = "${var.app_name}-dlq"

}



# S3 Notification to Lambda

resource "aws_s3_bucket_notification" "lambda_trigger" {
  bucket = aws_s3_bucket.main.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.main.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix = ""
 filter_suffix = ""

  }
}

data "aws_availability_zones" "available" {}

# -------- outputs.tf --------

output "s3_bucket_arn" {
  value = aws_s3_bucket.main.arn
}

output "lambda_function_arn" {
 value = aws_lambda_function.main.arn
}

output "s3_logs_bucket_arn" {
  value = aws_s3_bucket.logs.arn
}
output "dlq_arn" {
  value       = aws_sqs_queue.dlq.arn
}

# -------- terraform.tfvars --------

app_name = "devops-genie"