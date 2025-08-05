

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

resource "aws_s3_bucket" "file_upload_bucket" {
  bucket = "file-upload-bucket-${random_id.file_upload_bucket_id.hex}"
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

 lifecycle {
    prevent_destroy = false
 }


}

resource "aws_s3_bucket_public_access_block" "file_upload_bucket" {
  bucket                  = aws_s3_bucket.file_upload_bucket.id
 block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "random_id" "file_upload_bucket_id" {
  byte_length = 8
}


resource "aws_cloudfront_distribution" "file_upload_distribution" {
  origin {
    domain_name = aws_s3_bucket.file_upload_bucket.bucket_regional_domain_name
    origin_id   = aws_s3_bucket.file_upload_bucket.id

    s3_origin_config {
      origin_access_identity = ""
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = aws_s3_bucket.file_upload_bucket.id
    viewer_protocol_policy = "redirect-to-https"


    forwarded_values {
      cookies {
        forward = "none"
      }

      query_string = false
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

 price_class = "PriceClass_All"
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

