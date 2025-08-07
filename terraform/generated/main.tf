

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

variable "app_name" {
  type        = string
  description = "Name of the application"
  default     = "devops-genie-appname"
}

# -------- main.tf --------

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "public_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.main.id

 route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

resource "aws_route_table_association" "public_a" {
 subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_eip" "nat_eip" {
  vpc = true
}

resource "aws_nat_gateway" "nat_gw" {
 allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_a.id
}


resource "aws_s3_bucket" "video_storage" {
  bucket = "${var.app_name}-video-storage"
  acl    = "private"

  versioning {
    enabled = true
  }

 server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
 sse_algorithm     = "AES256"
      }
    }
  }

  lifecycle_rule {
    id      = "expire_after_30_days"
 enabled = true
    prefix  = ""

    expiration {
      days = 30
    }
  }

 logging {
    target_bucket = aws_s3_bucket.log_bucket.id
    target_prefix = "log/"
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
 sse_algorithm     = "AES256"
      }
    }
  }


 lifecycle_rule {
    id      = "expire_after_30_days"
 enabled = true
    prefix  = ""

    expiration {
 days = 30
    }
 }
}


resource "aws_lambda_function" "video_processing" {
  filename      = "lambda_function.zip" # Replace with your zipped code
  function_name = "${var.app_name}-video-processing"
  handler       = "index.handler"
  runtime       = "nodejs16.x"


  s3_bucket = "devops-genie-lambda-bucket" # Replace with your bucket if you're using one
  s3_key    = "lambda_function.zip"


 memory_size = 128
  timeout     = 30


 dead_letter_config {
    target_arn = aws_sqs_queue.lambda_dlq.arn
  }
}


resource "aws_sqs_queue" "lambda_dlq" {
  name = "${var.app_name}-lambda-dlq"
}



resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name = "/aws/lambda/${aws_lambda_function.video_processing.function_name}"
  retention_in_days = 30
}


resource "aws_s3_bucket_notification" "s3_trigger_lambda" {
  bucket = aws_s3_bucket.video_storage.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.video_processing.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = ""
    filter_suffix = ""
  }


 depends_on = [aws_lambda_permission.allow_s3_invoke_lambda]
}


resource "aws_lambda_permission" "allow_s3_invoke_lambda" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.video_processing.function_name
  principal     = "s3.amazonaws.com"
 source_arn = aws_s3_bucket.video_storage.arn
}



data "aws_availability_zones" "available" {}

# -------- outputs.tf --------

output "video_storage_bucket_arn" {
  value = aws_s3_bucket.video_storage.arn
}

output "video_processing_lambda_arn" {
 value = aws_lambda_function.video_processing.arn
}

output "lambda_dlq_url" {
  value = aws_sqs_queue.lambda_dlq.url
}

output "log_bucket_arn" {
  value = aws_s3_bucket.log_bucket.arn
}

# -------- terraform.tfvars --------

app_name = "devops-genie-appname"