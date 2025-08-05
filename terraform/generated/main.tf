

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



# -------- main.tf --------

# VPC and Networking

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
 map_public_ip_on_launch = true

}

resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
}


resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

resource "aws_route_table_association" "public_subnet_association" {
 subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_route_table.id
}

data "aws_availability_zones" "available" {}

resource "aws_eip" "nat_eip" {
  vpc = true
}

resource "aws_nat_gateway" "nat_gateway" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet.id

  tags = {
    Name = "nat-gateway"
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gateway.id
  }
}

resource "aws_route_table_association" "private_subnet_association" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_route_table.id
}

#S3 Example for Data Ingestion and Analytics Feature
resource "aws_s3_bucket" "data_lake" {
  bucket = "my-data-lake-bucket"
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
 sse_algorithm = "AES256"
      }
    }
  }

  versioning {
    enabled = true
  }

  lifecycle_rule {
    id      = "log"
    enabled = true

    prefix = "log/"
    transition {
      days          = 30
      storage_class = "STANDARD_IA" # Infrequent Access
    }
    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }

}

# Example SQS queue for Search Service
resource "aws_sqs_queue" "search_queue" {
  name                      = "search-queue"
  delay_seconds             = 90
  max_message_size         = 2048
  message_retention_seconds = 86400
  visibility_timeout        = 30
}

resource "aws_sqs_queue_policy" "search_queue_policy" {
  queue_url = aws_sqs_queue.search_queue.id

  policy = jsonencode({
    Version = "2012-10-17",
    Id      = "sqspolicy",
    Statement = [
      {
        Sid    = "First",
        Effect = "Allow",
        Principal = "*",
        Action   = "sqs:*",
        Resource = aws_sqs_queue.search_queue.arn,
        Condition = {
          ArnEquals = {
            "aws:SourceArn": "*"
          }
        }
      },
    ]
  })

}

# -------- outputs.tf --------

output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_id" {
 value = aws_subnet.public_subnet.id
}

output "private_subnet_id" {
  value = aws_subnet.private_subnet.id
}


output "s3_bucket_arn" {
  value = aws_s3_bucket.data_lake.arn
}

output "sqs_queue_url" {
 value = aws_sqs_queue.search_queue.url
}

# -------- terraform.tfvars --------

