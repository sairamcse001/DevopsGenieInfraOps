

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

variable "app_name" {
  type        = string
  description = "Name of the application"
  default     = "devops-genie"
}

# -------- main.tf --------

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  instance_tenancy    = "default"
  enable_dns_support   = true
  enable_dns_hostnames = true
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}



data "aws_availability_zones" "available" {}

resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
 map_public_ip_on_launch = true

}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
 map_public_ip_on_launch = true
}

resource "aws_eip" "nat_eip" {
 vpc = true
}


resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_1.id

  depends_on = [aws_internet_gateway.main]
}


resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
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


resource "aws_s3_bucket" "main" {
  bucket = "${var.app_name}-bucket"

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
    id      = "auto_delete_after_30_days"
    enabled = true

    expiration {
      days = 30
    }
  }


}

resource "aws_s3_bucket" "logging_bucket" {
  bucket = "${var.app_name}-logging-bucket"

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
    id      = "auto_delete_after_30_days"
    enabled = true

    expiration {
      days = 30
    }
  }

 logging {
    target_bucket = aws_s3_bucket.logging_bucket.id
    target_prefix = "log/"
  }
}

resource "aws_s3_bucket_logging" "main_bucket_logging" {
 target_bucket = aws_s3_bucket.logging_bucket.id
  target_prefix = "log/"
  bucket        = aws_s3_bucket.main.id
}



resource "aws_lambda_function" "main" {
  filename         = "lambda.zip"
  function_name    = "${var.app_name}-lambda"
  role             = "arn:aws:iam::123456789012:role/lambda_basic_execution" # Placeholder, IAM is excluded as per instructions
 handler          = "main"
  runtime          = "python3.9"
  source_code_hash = filebase64sha256("lambda.zip")
}



resource "aws_sqs_queue" "dlq" {
  name = "${var.app_name}-dlq"
}

resource "aws_lambda_event_source_mapping" "s3_trigger" {
  batch_size      = 10
  enabled         = true
  event_source_arn = aws_s3_bucket.main.arn
  function_name   = aws_lambda_function.main.arn

}



resource "aws_cloudwatch_log_group" "lambda" {
  name = "/aws/lambda/${aws_lambda_function.main.function_name}"
  retention_in_days = 30
}




resource "aws_s3_bucket_notification" "lambda_trigger" {
  bucket = aws_s3_bucket.main.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.main.arn
    events              = ["s3:ObjectCreated:*"]
 filter_prefix = "input/"
  }
}

resource "aws_s3_bucket_policy" "main" {
  bucket = aws_s3_bucket.main.id
  policy = data.aws_iam_policy_document.lambda_trigger_policy.json
}



data "aws_iam_policy_document" "lambda_trigger_policy" {
  statement {
    actions = ["s3:GetBucketLocation", "s3:ListBucket"]
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

 resources = [
      aws_s3_bucket.main.arn,
      "${aws_s3_bucket.main.arn}/*", # Add this to avoid access denied
    ]
  }
  statement {
    actions = [
     "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject"
    ]
    effect = "Allow"
 principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

 resources = [
      aws_s3_bucket.main.arn,
      "${aws_s3_bucket.main.arn}/*",
    ]

 condition {
      test     = "ArnLike"
      variable = "AWS:SourceArn"
      values   = [aws_s3_bucket.main.arn]
    }

  }

}

# -------- outputs.tf --------

output "lambda_function_name" {
  value       = aws_lambda_function.main.function_name
  description = "Lambda function name"
}

output "s3_bucket_name" {
  value       = aws_s3_bucket.main.bucket
  description = "S3 Bucket name"
}

output "s3_logging_bucket_name" {
  value       = aws_s3_bucket.logging_bucket.bucket
  description = "S3 Logging Bucket name"
}


output "sqs_dlq_name" {
  value       = aws_sqs_queue.dlq.name
  description = "SQS Dead Letter Queue name"
}

# -------- terraform.tfvars --------

app_name = "devops-genie"