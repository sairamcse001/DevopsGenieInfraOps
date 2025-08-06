

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
  type = string
  default = "default"
  description = "Prefix for resource names"
}

# -------- main.tf --------

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "public_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
}

resource "aws_subnet" "public_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.101.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.102.0/24"
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
 subnet_id     = aws_subnet.public_a.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
 vpc_id = aws_vpc.main.id

 route {
   cidr_block     = "0.0.0.0/0"
   nat_gateway_id = aws_nat_gateway.nat.id
 }
}


resource "aws_route_table_association" "private_a" {
 subnet_id      = aws_subnet.private_a.id
 route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_b" {
 subnet_id      = aws_subnet.private_b.id
 route_table_id = aws_route_table.private.id
}

data "aws_availability_zones" "available" {}

resource "aws_dynamodb_table" "account_management" {
  name         = "${var.name_prefix}-account-management"
 hash_key = "id"
  billing_mode = "PAY_PER_REQUEST"
 attribute {
   name = "id"
   type = "S"
 }
}


resource "aws_s3_bucket" "default" {
  bucket = "${var.name_prefix}-default-bucket"
}

resource "aws_iam_role" "lambda_role" {
 name = "${var.name_prefix}-lambda_role"
 assume_role_policy = jsonencode({
   Version = "2012-10-17",
   Statement = [
     {
       Action = "sts:AssumeRole",
       Effect = "Allow",
       Principal = {
         Service = "lambda.amazonaws.com"
       }
     },
   ]
 })
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
 name = "/aws/lambda/${var.name_prefix}-default-lambda"
 retention_in_days = 7
}

# -------- outputs.tf --------

output "vpc_id" {
 value = aws_vpc.main.id
}

output "dynamodb_arn" {
 value = aws_dynamodb_table.account_management.arn
}

output "s3_bucket_arn" {
  value = aws_s3_bucket.default.arn
}

# -------- terraform.tfvars --------

name_prefix = "example"