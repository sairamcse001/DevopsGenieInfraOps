

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
 region = "us-east-1" # Default AWS region
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
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "${var.app_name}-vpc"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "${var.app_name}-igw"
  }
}



resource "aws_subnet" "public_1" {
 cidr_block = "10.0.1.0/24"
 vpc_id     = aws_vpc.main.id
 availability_zone = data.aws_availability_zones.available.names[0]
 tags = {
   Name = "${var.app_name}-public-subnet-1"
 }
}

resource "aws_subnet" "public_2" {
  cidr_block = "10.0.2.0/24"
 vpc_id     = aws_vpc.main.id
 availability_zone = data.aws_availability_zones.available.names[1]
 tags = {
   Name = "${var.app_name}-public-subnet-2"
 }
}


data "aws_availability_zones" "available" {}




resource "aws_eip" "nat_eip" {
 vpc = true
 tags = {
   Name = "${var.app_name}-nat-eip"
 }
}


resource "aws_nat_gateway" "gw" {
 allocation_id = aws_eip.nat_eip.id
 subnet_id     = aws_subnet.public_1.id
 tags = {
   Name = "${var.app_name}-nat-gw"
 }
}

resource "aws_route_table" "public" {
 vpc_id = aws_vpc.main.id

 route {
   cidr_block = "0.0.0.0/0"
   gateway_id = aws_internet_gateway.gw.id
 }
 tags = {
   Name = "${var.app_name}-public-route-table"
 }

}


resource "aws_route_table_association" "public_1" {
 subnet_id      = aws_subnet.public_1.id
 route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_2" {
 subnet_id      = aws_subnet.public_2.id
 route_table_id = aws_route_table.public.id
}


# S3 Buckets
resource "aws_s3_bucket" "main" {
  bucket = "${var.app_name}-s3-bucket"
  acl    = "private"


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

 lifecycle {
    rule {
      id = "auto-delete-after-30-days"
      enabled = true
      expiration {
        days = 30
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
 acl    = "log-delivery-write"
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
 lifecycle {
 rule {
   id = "auto-delete-after-30-days"
   enabled = true
   expiration {
     days = 30
    }
  }
 }
}

# Lambda Function
resource "aws_lambda_function" "main" {
 filename         = "lambda.zip" # Replace with your lambda zip file
 function_name = "${var.app_name}-lambda"
 handler          = "index.handler"
 runtime          = "nodejs16.x"
 role = "arn:aws:iam::xxxxxxxxxxxx:role/lambda_basic_execution" # Placeholder - NO IAM in this exercise, use existing role
 memory_size = 128 # Default
 timeout = 30 # Default

 dead_letter_config {
   target_arn = aws_sqs_queue.dlq.arn
 }
}
resource "aws_cloudwatch_log_group" "lambda_log_group" {
 name = "/aws/lambda/${aws_lambda_function.main.function_name}"
 retention_in_days = 30
}

# DLQ
resource "aws_sqs_queue" "dlq" {
  name = "${var.app_name}-dlq"
}



# S3 Notification to Lambda
resource "aws_s3_bucket_notification" "main" {
  bucket = aws_s3_bucket.main.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.main.arn
    events              = ["s3:ObjectCreated:*"]
  }
}


# Add bucket policy to grant Lambda permissions to be triggered by S3


resource "aws_s3_bucket_policy" "main" {
  bucket = aws_s3_bucket.main.id

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "s3:Get*",
      "Resource": [
       "arn:aws:s3:::${aws_s3_bucket.main.id}",
       "arn:aws:s3:::${aws_s3_bucket.main.id}/*"
 ]
    },
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::${aws_s3_bucket.main.id}"
 }
   ]
 }
POLICY
}

# -------- outputs.tf --------

output "s3_bucket_arn" {
  value = aws_s3_bucket.main.arn
}

output "lambda_function_arn" {
  value = aws_lambda_function.main.arn
}

output "dlq_url" {
 value = aws_sqs_queue.dlq.url
}

output "vpc_id" {
 value = aws_vpc.main.id
}

# -------- terraform.tfvars --------

app_name = "devops-genie"