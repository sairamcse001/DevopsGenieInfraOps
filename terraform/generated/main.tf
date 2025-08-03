resource "random_id" "video_upload" {
  byte_length = 8
}

# --- Video Upload Service ---

resource "aws_s3_bucket" "video_upload_bucket" {
  bucket = var.video_upload_bucket_name
 acl    = "private"
}

resource "aws_s3_bucket_versioning" "video_upload_bucket_versioning" {
  bucket = aws_s3_bucket.video_upload_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}




resource "aws_sqs_queue" "video_processing_queue" {
  name = "video-processing-queue"
}


resource "aws_api_gateway_rest_api" "video_upload_api" {
  name        = "video_upload_api"
  description = "API Gateway for video uploads"
}



# --- Video Playback Service ---

resource "aws_dynamodb_table" "video_playback_table" {
 name           = var.video_playback_table_name
 billing_mode   = "PAY_PER_REQUEST"
 hash_key       = "video_id"
 attribute {
   name = "video_id"
   type = "S"
 }

}


resource "aws_api_gateway_rest_api" "video_playback_api" {
  name        = "video_playback_api"
  description = "API Gateway for video playback"

}



resource "aws_cloudfront_distribution" "video_playback_distribution" {
  origin {
    domain_name = aws_s3_bucket.video_upload_bucket.bucket_regional_domain_name
    origin_id   = "s3_origin"

    s3_origin_config {
      origin_access_identity = "origin-access-identity/cloudfront/xxxxxxxxxxxxxx" # Replace with actual OAI
    }


  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Video Playback Distribution"
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "s3_origin"
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
  }

 price_class = "PriceClass_100"
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

}



# --- Video Processing Pipeline ---


resource "aws_lambda_function" "video_processing_lambda" {
# Configuration for Lambda function
}


resource "aws_media_convert_queue" "video_processing_queue" {
  name = "video-processing-queue"
}