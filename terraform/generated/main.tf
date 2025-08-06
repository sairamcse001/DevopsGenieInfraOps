

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



# -------- main.tf --------

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true

  tags = {
    Name = "main-vpc"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main-igw"
  }
}

resource "aws_subnet" "public_subnet_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
 map_public_ip_on_launch = true

  tags = {
    Name = "public_subnet_a"
  }
}


resource "aws_eip" "nat_eip" {
 vpc = true
}

resource "aws_nat_gateway" "gw" {
 allocation_id = aws_eip.nat_eip.id
 subnet_id     = aws_subnet.public_subnet_a.id

  tags = {
    Name = "main-nat-gateway"
  }
}

resource "aws_subnet" "private_subnet_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
 availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "private_subnet_a"
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
 gateway_id = aws_nat_gateway.gw.id
  }

  tags = {
    Name = "private_route_table"
  }
}

resource "aws_route_table_association" "private_route_table_association_a" {
  subnet_id      = aws_subnet.private_subnet_a.id
  route_table_id = aws_route_table.private_route_table.id
}



data "aws_availability_zones" "available" {}

resource "aws_s3_bucket" "homepage_bucket" {
  bucket = "homepage-bucket-${random_id.bucket_id.hex}"
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

 lifecycle_rule {
    id      = "remove_old_versions"
    enabled = true

    noncurrent_version_expiration {
      days = 90
    }

    abort_incomplete_multipart_upload_days = 7
  }
}

resource "random_id" "bucket_id" {
  byte_length = 8
}

# -------- outputs.tf --------

output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_a_id" {
  value = aws_subnet.public_subnet_a.id
}


output "private_subnet_a_id" {
  value = aws_subnet.private_subnet_a.id
}

output "s3_bucket_arn" {
 value = aws_s3_bucket.homepage_bucket.arn
}

output "s3_bucket_id" {
 value = aws_s3_bucket.homepage_bucket.id
}

# -------- terraform.tfvars --------

