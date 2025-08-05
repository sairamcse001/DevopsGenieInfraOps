

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

# VPC and Networking

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
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




resource "aws_eip" "nat_eip" {
 vpc = true
}


resource "aws_nat_gateway" "nat" {
 allocation_id = aws_eip.nat_eip.id
 subnet_id     = aws_subnet.public_1.id
}

resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.10.0/24"
  availability_zone = "us-east-1a"
}



resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
}



resource "aws_route_table_association" "private_1" {
 subnet_id      = aws_subnet.private_1.id
  route_table_id = aws_route_table.private.id
}


# Video Upload Service

resource "aws_s3_bucket" "video_upload_bucket" {
  bucket = "video-upload-bucket-${random_id.default.hex}"
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
    id = "remove_old_versions"

    noncurrent_version_expiration {
      days = 90
    }
  }
}


resource "aws_api_gateway_rest_api" "video_upload_api" {
  name        = "video_upload_api"
}


resource "aws_sqs_queue" "video_upload_queue" {
 name = "video_upload_queue"
}



# Video Processing Pipeline




resource "aws_sqs_queue" "video_processing_queue" {
 name = "video_processing_queue"
}



resource "aws_lambda_function" "video_processing_lambda" {
  filename      = "dummy_lambda.zip" # Replace with your lambda zip file
  function_name = "video_processing_lambda"
  role          = aws_iam_role.video_processing_lambda_role.arn
  handler       = "main.handler" # Replace with your handler
  runtime = "python3.9"


  source_code_hash = filebase64sha256("dummy_lambda.zip")


}


resource "aws_cloudwatch_log_group" "video_processing_lambda_log_group" {
  name = "/aws/lambda/${aws_lambda_function.video_processing_lambda.function_name}"
  retention_in_days = 7
}


resource "aws_iam_role" "video_processing_lambda_role" {
 name = "video_processing_lambda_role"


  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}



# Video Playback Service


resource "aws_api_gateway_rest_api" "video_playback_api" {
  name        = "video_playback_api"
}



resource "aws_cloudfront_distribution" "video_playback_distribution" {
 origin {
    domain_name = aws_s3_bucket.video_upload_bucket.bucket_regional_domain_name
 origin_id   = aws_s3_bucket.video_upload_bucket.bucket
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html" # Example


  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = aws_s3_bucket.video_upload_bucket.bucket
    viewer_protocol_policy = "redirect-to-https"


    forwarded_values {
      query_string = false


      cookies {
 forward = "none"
      }
    }


 min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
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



resource "aws_dynamodb_table" "video_playback_metadata" {
 name         = "video_playback_metadata"
 billing_mode = "PAY_PER_REQUEST"
 hash_key     = "video_id"


 attribute {
    name = "video_id"
    type = "S"
  }

}

resource "random_id" "default" {
  byte_length = 8
}

# -------- outputs.tf --------

output "video_upload_bucket_arn" {
  value = aws_s3_bucket.video_upload_bucket.arn
}

output "video_upload_queue_url" {
 value = aws_sqs_queue.video_upload_queue.url
}


output "video_processing_lambda_arn" {
 value = aws_lambda_function.video_processing_lambda.arn
}



output "video_processing_queue_url" {
 value = aws_sqs_queue.video_processing_queue.url
}

output "video_playback_distribution_domain_name" {
 value = aws_cloudfront_distribution.video_playback_distribution.domain_name
}


output "video_playback_metadata_arn" {
 value = aws_dynamodb_table.video_playback_metadata.arn
}

# -------- terraform.tfvars --------

