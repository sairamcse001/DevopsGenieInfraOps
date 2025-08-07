

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

# S3 Buckets

resource "aws_s3_bucket" "main_bucket" {
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
    id      = "delete_after_30_days"
    enabled = true
    prefix  = "/"

    expiration {
      days = 30
    }
  }

 logging {
    target_bucket = aws_s3_bucket.log_bucket.id
    target_prefix = "log/"
  }
}


resource "aws_s3_bucket" "log_bucket" {
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
    id      = "delete_after_30_days"
    enabled = true
    prefix  = "/"
    expiration {
      days = 30
    }
  }
}



# Lambda Function and related resources

resource "aws_lambda_function" "main_lambda" {
  function_name = "${var.app_name}-lambda"
  handler       = "index.handler" # Replace with your handler
  runtime       = "nodejs16.x" # Replace with your runtime


  # Replace with inline code or s3 reference
  filename         = "lambda.zip"
  source_code_hash = filebase64sha256("lambda.zip")


  s3_bucket = aws_s3_bucket.main_bucket.id
  s3_key    = "lambda.zip" # Replace as needed


 dead_letter_config {
    target_arn = aws_sqs_queue.dlq.arn
  }

}



resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name = "/aws/lambda/${aws_lambda_function.main_lambda.function_name}"
  retention_in_days = 30
}


resource "aws_sqs_queue" "dlq" {
  name = "${var.app_name}-dlq"
}


# S3 Notification to trigger Lambda
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.main_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.main_lambda.arn
    events              = ["s3:ObjectCreated:*"]

   filter_prefix = "" # Example filter

   filter_suffix = "" # Example filter
  }
}




# VPC Resources (Default settings)
resource "aws_vpc" "default" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "public_subnet" {
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  vpc_id            = aws_vpc.default.id

}



resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.default.id
}


resource "aws_default_route_table" "main" {
  default_route_table_id = aws_vpc.default.default_route_table_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id

  }
}





data "aws_availability_zones" "available" {}

# -------- outputs.tf --------

output "main_bucket_id" {
  value = aws_s3_bucket.main_bucket.id
}

output "lambda_function_arn" {
  value = aws_lambda_function.main_lambda.arn
}

output "dlq_url" {
  value = aws_sqs_queue.dlq.url
}

output "log_bucket_id" {
  value = aws_s3_bucket.log_bucket.id
}

# -------- terraform.tfvars --------

app_name = "devops-genie"