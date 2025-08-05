

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

variable "s3_bucket_name_prefix" {
  type        = string
  default     = "file-upload-bucket"
  description = "Prefix for the S3 bucket name"
}

variable "cloudfront_distribution_comment" {
 type = string
 default = "File Upload CloudFront Distribution"
 description = "Comment for the CloudFront Distribution"
}

# -------- main.tf --------

resource "aws_s3_bucket" "file_upload_bucket" {
  bucket = "${var.s3_bucket_name_prefix}-${random_id.file_upload_bucket_suffix.hex}"
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
    id = "remove_old_files"
  enabled = true

 prefix = ""

 transitions {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transitions {
        days          = 90
      storage_class = "GLACIER"
    }

    expiration {
 days = 365
    }
  }

  logging {
    target_bucket = "${var.s3_bucket_name_prefix}-${random_id.file_upload_bucket_suffix.hex}-logs"
 target_prefix = "logs/"
 }

}



resource "aws_s3_bucket" "file_upload_logs_bucket" {
  bucket = "${var.s3_bucket_name_prefix}-${random_id.file_upload_bucket_suffix.hex}-logs"
  acl    = "log-delivery-write"

  lifecycle_rule {
        id = "remove_old_logs"
  enabled = true

  prefix = ""

  expiration {
 days = 30
 }

  }



}


resource "aws_cloudfront_distribution" "file_upload_distribution" {
 origin {
    domain_name = aws_s3_bucket.file_upload_bucket.bucket_regional_domain_name
    origin_id   = aws_s3_bucket.file_upload_bucket.bucket

    s3_origin_config {
 }

  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = var.cloudfront_distribution_comment
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
 target_origin_id = aws_s3_bucket.file_upload_bucket.bucket
    viewer_protocol_policy = "redirect-to-https"
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

resource "random_id" "file_upload_bucket_suffix" {
  byte_length = 8
}

# -------- outputs.tf --------

output "s3_bucket_arn" {
  value = aws_s3_bucket.file_upload_bucket.arn
}

output "s3_bucket_id" {
 value = aws_s3_bucket.file_upload_bucket.id
}

output "cloudfront_distribution_domain_name" {
  value = aws_cloudfront_distribution.file_upload_distribution.domain_name
}

output "cloudfront_distribution_id" {
 value = aws_cloudfront_distribution.file_upload_distribution.id
}

# -------- terraform.tfvars --------

