

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

# VPC
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


resource "aws_eip" "nat_eip" {
 vpc = true
 tags = {
    Name = "${var.app_name}-nat-eip"
  }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_1.id
 tags = {
    Name = "${var.app_name}-nat-gateway"
  }
}



# S3 Buckets
resource "aws_s3_bucket" "main" {
  bucket = "${var.app_name}-main-bucket"

 lifecycle {
    prevent_destroy = false
 }


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

  logging {
    target_bucket = "${var.app_name}-log-bucket"
    target_prefix = "log/"
  }

  lifecycle_rule {
    id                                     = "delete-after-30-days"
    enabled                                = true
    expiration {
 days = 30
    }
  }

  tags = {
    Name = "${var.app_name}-main-bucket"
  }

}



resource "aws_s3_bucket" "log_bucket" {
  bucket = "${var.app_name}-log-bucket"

 lifecycle {
    prevent_destroy = false
 }

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

 tags = {
    Name = "${var.app_name}-log-bucket"
  }
}


# Lambda Function and supporting resources
resource "aws_lambda_function" "main" {
  function_name = "${var.app_name}-lambda"

  # Replace with inline code or .zip file as needed
  filename      = "lambda_function.zip" # Replace or use "handler" and "runtime" for inline functions
  source_code_hash = filebase64sha256("lambda_function.zip")
  handler       = "index.handler"
  runtime = "nodejs16.x" # Or your desired runtime



  s3_bucket = aws_s3_bucket.main.id
  s3_key    = "lambda_function.zip"

  tags = {
    Name = "${var.app_name}-lambda"
  }

}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.main.function_name}"
  retention_in_days = 30
}



resource "aws_sqs_queue" "dlq" {
  name = "${var.app_name}-dlq"

  tags = {
    Name = "${var.app_name}-dlq"
  }
}



# S3 Notification to Lambda
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.main.bucket

  lambda_function {
    lambda_function_arn = aws_lambda_function.main.arn
    events              = ["s3:ObjectCreated:*"]

 filter_prefix = ""
    filter_suffix = ""
  }

 depends_on = [aws_lambda_permission.allow_bucket_to_trigger_lambda]

}



resource "aws_lambda_permission" "allow_bucket_to_trigger_lambda" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.main.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.main.arn
}

data "aws_availability_zones" "available" {}

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

