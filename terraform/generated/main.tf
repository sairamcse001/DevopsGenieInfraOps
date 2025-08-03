# ===== Provider Configuration =====
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ===== Variables =====
variable "aws_region" {
  type        = string
  description = "The AWS region to deploy the infrastructure in."
  default     = "us-west-2"
}

variable "video_upload_bucket_name" {
  type        = string
  description = "The name of the S3 bucket for video uploads."
  default     = "video-uploads-${random_id.video_upload.hex}"
}

variable "video_playback_table_name" {
  type        = string
  description = "Name of the DynamoDB table to store video metadata"
  default     = "video_playback_metadata"
}

# ===== Random ID Resource =====
resource "random_id" "video_upload" {
  byte_length = 8
}

# ===== Video Upload Service =====
resource "aws_s3_bucket" "video_upload_bucket" {
  bucket = var.video_upload_bucket_name
  acl    = "private"

  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_s3_bucket_versioning" "video_upload_bucket_versioning" {
  bucket = aws_s3_bucket.video_upload_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_sqs_queue" "video_upload_queue" {
  name = "video_upload_queue"
}

# ===== Video Playback Service =====
resource "aws_dynamodb_table" "video_playback_table" {
  name         = var.video_playback_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "video_id"

  attribute {
    name = "video_id"
    type = "S"
  }
}

resource "aws_cloudfront_distribution" "video_playback_distribution" {
  origin {
    domain_name = aws_s3_bucket.video_upload_bucket.bucket_regional_domain_name
    origin_id   = "s3-video-upload-origin"

    s3_origin_config {
      origin_access_identity = "origin-access-identity/cloudfront/ABCDEFGHIJKLMN" # Replace with actual OAI
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "s3-video-upload-origin"
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
  }

  price_class = "PriceClass_All"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# ===== Video Processing Pipeline =====
resource "aws_sqs_queue" "video_processing_queue" {
  name = "video_processing_queue"
}

resource "aws_lambda_function" "video_processing_lambda" {
  filename      = "lambda_function.zip" # Replace with actual path to deployment zip
  function_name = "video_processing_lambda"
  handler       = "index.handler"
  role          = "arn:aws:iam::123456789012:role/lambda_basic_execution" # Replace with actual IAM role ARN
  runtime       = "nodejs16.x"
}

# ===== Outputs =====
output "video_upload_bucket_arn" {
  value = aws_s3_bucket.video_upload_bucket.arn
}

output "video_upload_queue_url" {
  value = aws_sqs_queue.video_upload_queue.url
}

output "video_playback_table_arn" {
  value = aws_dynamodb_table.video_playback_table.arn
}

output "video_playback_cloudfront_domain_name" {
  value = aws_cloudfront_distribution.video_playback_distribution.domain_name
}

output "video_processing_queue_url" {
  value = aws_sqs_queue.video_processing_queue.url
}

output "video_processing_lambda_arn" {
  value = aws_lambda_function.video_processing_lambda.arn
}
