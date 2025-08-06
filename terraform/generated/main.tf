

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

variable "name_prefix" {
  type        = string
  default     = "my-app"
  description = "Prefix for resource names"
}

# -------- main.tf --------

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
}

resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
}


resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
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

resource "aws_eip" "nat_eip" {
  vpc = true
}

resource "aws_nat_gateway" "nat" {
 allocation_id = aws_eip.nat_eip.id
 subnet_id     = aws_subnet.public_1.id
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
}


resource "aws_route_table_association" "private_subnet_association" {
  subnet_id      = aws_subnet.private_1.id
  route_table_id = aws_route_table.private_route_table.id
}




resource "aws_dynamodb_table" "user_account_table" {
  name         = "${var.name_prefix}-user-account-table"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "userId"
  attribute {
    name = "userId"
    type = "S"
  }
}

resource "aws_s3_bucket" "usage_tracking_bucket" {
  bucket = "${var.name_prefix}-usage-tracking-bucket"

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
 sse_algorithm     = "AES256"
      }
    }
  }

}




resource "aws_lambda_function" "billing_lambda" {
 filename      = "billing_lambda.zip" # Placeholder - no actual code provided
 function_name = "${var.name_prefix}-billing-lambda"
 handler       = "index.handler" # Placeholder
 runtime       = "nodejs16.x"
 role          = aws_iam_role.billing_lambda_role.arn

}

resource "aws_iam_role" "billing_lambda_role" {
 name = "${var.name_prefix}-billing-lambda-role"

 assume_role_policy = jsonencode({
 Version = "2012-10-17"
 Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
 Principal = {
          Service = "lambda.amazonaws.com"
 }
      },
    ]
 })
}

# -------- outputs.tf --------

output "dynamodb_table_arn" {
  value = aws_dynamodb_table.user_account_table.arn
}

output "s3_bucket_arn" {
 value = aws_s3_bucket.usage_tracking_bucket.arn
}
output "lambda_function_arn" {
  value = aws_lambda_function.billing_lambda.arn
}

# -------- terraform.tfvars --------

name_prefix = "my-app"