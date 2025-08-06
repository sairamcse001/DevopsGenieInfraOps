

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

variable "dynamodb_table_name_prefix" {
  type        = string
  description = "Prefix for DynamoDB table names"
  default     = "default"
}

variable "lambda_function_name_prefix" {
  type        = string
  description = "Prefix for Lambda function names"
  default     = "default"
}

variable "kinesis_stream_name_prefix" {
 type = string
 description = "Prefix for Kinesis stream names"
 default = "default"
}


variable "s3_bucket_name_prefix" {
 type = string
 description = "Prefix for S3 bucket names"
 default = "default"
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

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

resource "aws_route_table_association" "public_1" {
 subnet_id      = aws_subnet.public_1.id
 route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "public_2" {
 subnet_id      = aws_subnet.public_2.id
 route_table_id = aws_route_table.public_route_table.id
}



data "aws_availability_zones" "available" {}


# User Management - DynamoDB

resource "aws_dynamodb_table" "user_management" {
 name         = "${var.dynamodb_table_name_prefix}-user-management"
 billing_mode = "PAY_PER_REQUEST"
 hash_key     = "userId"
 attribute {
   name = "userId"
   type = "S"
 }
}


# Subscription Management - DynamoDB
resource "aws_dynamodb_table" "subscription_management" {
 name         = "${var.dynamodb_table_name_prefix}-subscription-management"
 billing_mode = "PAY_PER_REQUEST"
 hash_key     = "subscriptionId"
 attribute {
   name = "subscriptionId"
   type = "S"
 }
}



# Usage Tracking - Kinesis

resource "aws_kinesis_stream" "usage_tracking" {
 name        = "${var.kinesis_stream_name_prefix}-usage-tracking"
 shard_count = 1
}

# -------- outputs.tf --------

output "dynamodb_user_management_arn" {
 value = aws_dynamodb_table.user_management.arn
}

output "dynamodb_subscription_management_arn" {
 value = aws_dynamodb_table.subscription_management.arn
}

output "kinesis_usage_tracking_arn" {
 value = aws_kinesis_stream.usage_tracking.arn
}

output "vpc_id" {
 value = aws_vpc.main.id
}

output "public_subnet_ids" {
 value = [aws_subnet.public_1.id, aws_subnet.public_2.id]
}

# -------- terraform.tfvars --------

