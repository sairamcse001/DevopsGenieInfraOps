

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
  default     = "devops-genie"
}

# -------- main.tf --------

# VPC and Networking

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "public_1" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
}

resource "aws_subnet" "public_2" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]
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

resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public_route_table.id
}
resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public_route_table.id
}

data "aws_availability_zones" "available" {}

resource "aws_eip" "nat_eip" {
 vpc = true
}

resource "aws_nat_gateway" "natgw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_1.id

  depends_on = [aws_internet_gateway.gw]
}

# S3 Buckets

resource "aws_s3_bucket" "main_bucket" {
  bucket = "${var.app_name}-main-bucket"

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
    id = "auto-delete-after-30-days"

    enabled = true

    prefix  = ""
    status = "Enabled"

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
  force_destroy = true


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
    id = "auto-delete-after-30-days"

    enabled = true

    prefix  = ""
    status = "Enabled"

    expiration {
      days = 30
    }

  }
}

# Lambda Function and Related Resources


resource "aws_lambda_function" "main_lambda" {
  function_name = "${var.app_name}-lambda"
  handler       = "index.handler"
  runtime = "nodejs16.x"


filename         = "lambda.zip"

source_code_hash = filebase64sha256("lambda.zip")
  memory_size = 128
  timeout = 30

 dead_letter_config {
    target_arn = aws_sqs_queue.dlq.arn
  }
}


resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name = "/aws/lambda/${aws_lambda_function.main_lambda.function_name}"

  retention_in_days = 30
}



resource "aws_sqs_queue" "dlq" {
 name = "${var.app_name}-dlq"

}

# S3 Bucket Notification to Lambda


resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.main_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.main_lambda.arn
    events              = ["s3:ObjectCreated:*"]

    filter_prefix = ""
    filter_suffix = ""
  }


}

# Bucket Policy


resource "aws_s3_bucket_policy" "allow_lambda_trigger" {

  bucket = aws_s3_bucket.main_bucket.id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "s3:GetBucketNotification",
      "Resource": "arn:aws:s3:::${aws_s3_bucket.main_bucket.id}"
    },
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "s3:ObjectCreated:*",
      "Resource": "arn:aws:s3:::${aws_s3_bucket.main_bucket.id}/*"
    }
  ]
}
EOF

}

# -------- outputs.tf --------

output "s3_bucket_arn" {
  value = aws_s3_bucket.main_bucket.arn
}

output "lambda_function_arn" {
  value = aws_lambda_function.main_lambda.arn
}

output "sqs_dlq_arn" {
 value = aws_sqs_queue.dlq.arn
}

output "s3_log_bucket_arn" {
 value = aws_s3_bucket.log_bucket.arn
}

output "vpc_id" {
 value = aws_vpc.main.id
}

# -------- terraform.tfvars --------

app_name = "devops-genie"