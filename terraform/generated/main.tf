

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

variable "s3_bucket_name_prefix" {
  type        = string
  description = "Prefix for S3 bucket names"
  default     = "devops-genie-appname"
}

# -------- main.tf --------

# VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.app_name}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.app_name}-igw"
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



resource "aws_eip" "nat" {
 vpc = true
}


resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_1.id
 depends_on = [aws_internet_gateway.main]
 tags = {
    Name = "${var.app_name}-nat"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id


  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id

  }

  tags = {
    Name = "${var.app_name}-public-route-table"
  }
}



resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id

}





# S3 Buckets
resource "aws_s3_bucket" "main" {
  bucket = "${var.s3_bucket_name_prefix}-storage"

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
    id      = "auto-delete-rule"
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
  bucket = "${var.s3_bucket_name_prefix}-logs"
   server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
 sse_algorithm = "AES256"
      }
    }
  }

  lifecycle_rule {

    id      = "auto-delete-rule"
    enabled = true
    expiration {
      days = 30
    }
  }


  force_destroy = true



}

resource "aws_s3_bucket_acl" "logs_acl" {
  bucket = aws_s3_bucket.logs.id
  acl    = "log-delivery-write"
}

# SQS Queue (DLQ)
resource "aws_sqs_queue" "dlq" {
  name = "${var.s3_bucket_name_prefix}-dlq"
}


# Lambda Function
resource "aws_lambda_function" "main" {
  function_name = "${var.s3_bucket_name_prefix}-lambda"
  handler       = "index.handler" # Replace with your handler
  runtime       = "nodejs16.x" # Replace with your runtime
  filename      = "lambda.zip" # Example zip
# Inline example - uncomment for inline code
#  handler = "index.handler"
#  runtime = "nodejs16.x"
#  inline_code = <<EOF
# exports.handler = async (event) => {
#   const response = {
#     statusCode: 200,
#     body: JSON.stringify('Hello from Lambda!'),
#   };
#   return response;
# };
# EOF


dead_letter_config {
    target_arn = aws_sqs_queue.dlq.arn
  }

}



# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${aws_lambda_function.main.function_name}"
  retention_in_days = 30
}


# S3 Bucket Notification to Lambda
resource "aws_s3_bucket_notification" "main" {
  bucket = aws_s3_bucket.main.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.main.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "uploads/"
  }

 depends_on = [aws_lambda_permission.s3_invoke_lambda]
}

resource "aws_lambda_permission" "s3_invoke_lambda" {
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

app_name = "devops-genie"
s3_bucket_name_prefix = "devops-genie-appname"