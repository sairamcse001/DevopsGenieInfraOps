

# -------- provider.tf --------

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region = "us-west-2"
}

# -------- variables.tf --------

variable "app_name" {
  type        = string
  description = "Name of the application"
  default     = "devops-genie"
}

# -------- main.tf --------

resource "aws_s3_bucket" "video_storage" {
  bucket = "${var.app_name}-video-storage"
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
    id      = "delete_old_videos"
    enabled = true

    expiration {
      days = 30
    }
  }


 logging {
    target_bucket = aws_s3_bucket.log_bucket.id
    target_prefix = "video-storage-logs/"
  }
}

resource "aws_s3_bucket" "log_bucket" {
  bucket = "${var.app_name}-log-bucket"
  acl    = "log-delivery-write"

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
    id      = "delete_old_logs"
    enabled = true
    expiration {
      days = 30
    }
 }


}

resource "aws_lambda_function" "video_processing" {
  function_name = "${var.app_name}-video-processing"
  handler       = "index.handler"
  runtime       = "nodejs16.x"
# Replace with your actual zip file
  filename      = "dummy_lambda.zip"
 source_code_hash = filebase64sha256("dummy_lambda.zip")


  s3_bucket = aws_s3_bucket.video_storage.id
  s3_key    = "dummy_lambda.zip"

}




resource "aws_sqs_queue" "dlq" {
  name = "${var.app_name}-dlq"

}


resource "aws_cloudwatch_log_group" "video_processing_log_group" {
  name = "/aws/lambda/${aws_lambda_function.video_processing.function_name}"
 retention_in_days = 30

}

resource "aws_s3_bucket_notification" "video_upload_notification" {
  bucket = aws_s3_bucket.video_storage.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.video_processing.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix = ""
    filter_suffix = ""
  }


}


resource "aws_default_vpc" "default_vpc" {}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_default_vpc.default_vpc.id
}


resource "aws_default_subnet" "default_subnet_az1" {
  availability_zone = data.aws_availability_zones.available.names[0]
}



resource "aws_default_route_table" "default_route_table" {
  default_route_table_id = aws_default_vpc.default_vpc.default_route_table_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

}

data "aws_availability_zones" "available" {}

# -------- outputs.tf --------

output "video_storage_bucket_arn" {
  value = aws_s3_bucket.video_storage.arn
}

output "video_processing_lambda_arn" {
  value = aws_lambda_function.video_processing.arn
}

# -------- terraform.tfvars --------

app_name = "devops-genie"