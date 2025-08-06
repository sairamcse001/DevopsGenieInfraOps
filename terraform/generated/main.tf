

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
  default     = "app"
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

resource "aws_subnet" "public_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
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



data "aws_availability_zones" "available" {}

resource "aws_eip" "nat" {
 vpc = true
}

resource "aws_nat_gateway" "gw" {
 allocation_id = aws_eip.nat.id
 subnet_id     = aws_subnet.public_1.id
}


resource "aws_dynamodb_table" "user_management" {
  name           = "${var.name_prefix}_user_table"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "id"
  attribute {
    name = "id"
    type = "S"
  }
}


resource "aws_s3_bucket" "usage_tracking" {
  bucket = "${var.name_prefix}-usage-tracking"
}

resource "aws_sqs_queue" "billing_service" {
  name = "${var.name_prefix}-billing-queue"
}

resource "aws_sqs_queue" "reward_system" {
 name = "${var.name_prefix}-reward-queue"
}

resource "aws_security_group" "allow_all" {
  name        = "${var.name_prefix}_allow_all"
  description = "Allow all inbound and outbound traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# -------- outputs.tf --------

output "dynamodb_table_arn" {
  value = aws_dynamodb_table.user_management.arn
}

output "s3_bucket_arn" {
 value = aws_s3_bucket.usage_tracking.arn
}

output "billing_queue_url" {
  value = aws_sqs_queue.billing_service.url
}

output "reward_queue_url" {
  value = aws_sqs_queue.reward_system.url
}

output "vpc_id" {
 value = aws_vpc.main.id
}

output "public_subnet_ids" {
 value = [aws_subnet.public_1.id, aws_subnet.public_2.id]
}

# -------- terraform.tfvars --------

name_prefix = "app"