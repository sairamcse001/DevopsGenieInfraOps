

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

variable "name_prefix" {
  type        = string
  default     = "ecommerce-platform"
  description = "Prefix for resource names"
}

# -------- main.tf --------

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "public_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
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


data "aws_availability_zones" "available" {}

resource "aws_s3_bucket" "default" {

}

resource "aws_sqs_queue" "default" {

}

# -------- outputs.tf --------

output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_id" {
  value = aws_subnet.public_1.id
}

output "private_subnet_id" {
 value = aws_subnet.private_1.id
}

output "s3_bucket_arn" {
 value = aws_s3_bucket.default.arn
}

output "sqs_queue_url" {
 value = aws_sqs_queue.default.url
}

# -------- terraform.tfvars --------

name_prefix = "ecommerce-platform"