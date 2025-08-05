# --------------------------------------------------
# Provider & Backend Configuration (Best Practices)
# --------------------------------------------------
 
terraform {
  required_version = ">= 1.3.0"
 
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}
 
provider "aws" {
  region     = "us-west-2" # Change as required
  access_key = "access_key"
  secret_key = "grArBukNDKMmjHXEf7WZYAz9B69q9XLLT10zS0iw"
}
 
# --------------------------------------------------
# Variables
# --------------------------------------------------
 
variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}
 
variable "environment" {
  description = "Environment name (e.g., dev, prod)"
  type        = string
  default     = "dev"
}
 
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}
 
variable "public_subnet_cidrs" {
  description = "List of public subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}
 
variable "private_subnet_cidrs" {
  description = "List of private subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}
 
variable "lambda_runtime" {
  description = "Runtime environment for Lambda"
  type        = string
  default     = "python3.9"
}
 
# --------------------------------------------------
# Random ID for Unique Naming
# --------------------------------------------------
 
resource "random_id" "default" {
  byte_length = 8
}
 
# --------------------------------------------------
# Networking (VPC, Subnets, IGW, NAT, Routes)
# --------------------------------------------------
 
# Module or inline networking can be used here.
# Keeping inline for demonstration.
 
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "vpc-${var.environment}"
  }
}
 
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}
 
resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  map_public_ip_on_launch = true
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
}
 
resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
}
 
data "aws_availability_zones" "available" {}
 
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
 
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}
 
resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
 
resource "aws_eip" "nat" {
  count = 1
  vpc   = true
}
 
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public[0].id
}
 
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
 
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
}
 
resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
 
# --------------------------------------------------
# S3 Bucket (Video Upload)
# --------------------------------------------------
 
resource "aws_s3_bucket" "video_upload" {
  bucket = "video-upload-${var.environment}-${random_id.default.hex}"
  force_destroy = true
 
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
    enabled = true
    noncurrent_version_expiration {
      days = 90
    }
  }
 
  tags = {
    Name        = "video-upload-${var.environment}"
    Environment = var.environment
  }
}
 
# --------------------------------------------------
# IAM Role for Lambda
# --------------------------------------------------
 
resource "aws_iam_role" "lambda_exec_role" {
  name = "video-lambda-role-${var.environment}"
 
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}
 
# --------------------------------------------------
# Lambda Function (Video Processing)
# --------------------------------------------------
 
resource "aws_lambda_function" "video_processing" {
  filename         = "dummy_lambda.zip"
  function_name    = "video_processing_${var.environment}"
  handler          = "main.handler"
  runtime          = var.lambda_runtime
  role             = aws_iam_role.lambda_exec_role.arn
  //source_code_hash = filebase64sha256("dummy_lambda.zip")
 
  tags = {
    Environment = var.environment
  }
}
 
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.video_processing.function_name}"
  retention_in_days = 7
}
 
# --------------------------------------------------
# SQS Queues
# --------------------------------------------------
 
resource "aws_sqs_queue" "upload" {
  name = "video-upload-queue-${var.environment}"
}
 
resource "aws_sqs_queue" "processing" {
  name = "video-processing-queue-${var.environment}"
}
 
# --------------------------------------------------
# API Gateway (Upload & Playback APIs)
# --------------------------------------------------
 
resource "aws_api_gateway_rest_api" "upload" {
  name = "upload-api-${var.environment}"
}
 
resource "aws_api_gateway_rest_api" "playback" {
  name = "playback-api-${var.environment}"
}
 
# --------------------------------------------------
# CloudFront (Playback CDN)
# --------------------------------------------------
 
resource "aws_cloudfront_distribution" "playback" {
  origin {
    domain_name = aws_s3_bucket.video_upload.bucket_regional_domain_name
    origin_id   = aws_s3_bucket.video_upload.id
  }
 
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
 
  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = aws_s3_bucket.video_upload.id
    viewer_protocol_policy = "redirect-to-https"
 
    forwarded_values {
      query_string = false
 
      cookies {
        forward = "none"
      }
    }
 
    min_ttl     = 0
    default_ttl = 86400
    max_ttl     = 31536000
  }
 
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
 
  viewer_certificate {
    cloudfront_default_certificate = true
  }
 
  tags = {
    Environment = var.environment
  }
}
 
# --------------------------------------------------
# DynamoDB (Playback Metadata)
# --------------------------------------------------
 
resource "aws_dynamodb_table" "metadata" {
  name         = "video-playback-metadata-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "video_id"
 
  attribute {
    name = "video_id"
    type = "S"
  }
 
  tags = {
    Environment = var.environment
  }
}
 
# --------------------------------------------------
# Outputs
# --------------------------------------------------
 
output "video_upload_bucket_arn" {
  value = aws_s3_bucket.video_upload.arn
}
 
output "video_processing_lambda_arn" {
  value = aws_lambda_function.video_processing.arn
}
 
output "video_upload_queue_url" {
  value = aws_sqs_queue.upload.url
}
 
output "video_processing_queue_url" {
  value = aws_sqs_queue.processing.url
}
 
output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.playback.domain_name
}
