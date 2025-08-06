

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

# VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "public_1" {
  cidr_block        = "10.0.1.0/24"
  vpc_id            = aws_vpc.main.id
  availability_zone = data.aws_availability_zones.available.names[0]
}


resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_1.id

  depends_on = [aws_internet_gateway.gw]
}

resource "aws_eip" "nat" {
  vpc = true
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

# S3 Buckets
resource "aws_s3_bucket" "main" {
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
    enabled = true
    id      = "auto-delete-rule"

    prefix  = ""

 expiration {
      days = 30
 }
  }

 logging {
    target_bucket = aws_s3_bucket.logs.id
    target_prefix = "log/"
  }
}



resource "aws_s3_bucket" "logs" {
  bucket = "${var.app_name}-log-bucket"

 server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm     = "AES256"
      }
    }
  }
}



# SQS Queue (DLQ)
resource "aws_sqs_queue" "dlq" {
  name = "${var.app_name}-dlq"
}

# Lambda Function
resource "aws_lambda_function" "main" {
  function_name = "${var.app_name}-lambda"
  handler       = "index.handler" # Placeholder, replace with actual handler
  runtime       = "nodejs16.x"
  memory_size = 128
 timeout = 30

  # Replace with inline code or zip file as needed
  filename         = "lambda.zip"
  source_code_hash = filebase64sha256("lambda.zip") # Create dummy zip file


  s3_bucket = aws_s3_bucket.main.id
  s3_key    = "lambda.zip"



  dead_letter_config {
 target_arn = aws_sqs_queue.dlq.arn
  }

}


# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda" {
  name = "/aws/lambda/${aws_lambda_function.main.function_name}"
  retention_in_days = 30
}



# S3 Notification to trigger Lambda
resource "aws_s3_bucket_notification" "lambda_trigger" {
  bucket = aws_s3_bucket.main.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.main.arn
    events              = ["s3:ObjectCreated:*"]
 filter_prefix = ""
  }
}


# Bucket policy
resource "aws_s3_bucket_policy" "allow_lambda_trigger" {
  bucket = aws_s3_bucket.main.id
  policy = data.aws_iam_policy_document.allow_lambda.json
}

data "aws_iam_policy_document" "allow_lambda" {
  statement {
    actions = ["s3:PutObject", "s3:PutObjectAcl"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    resources = ["arn:aws:s3:::${aws_s3_bucket.main.id}/*"]

 condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["${aws_lambda_function.main.arn}"]
    }
  }
}
# Placeholder empty zip file for now
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "lambda.zip"

 content {
    text = "placeholder"
  }
}



data "aws_availability_zones" "available" {}

# -------- outputs.tf --------

output "s3_bucket_main_arn" {
  value = aws_s3_bucket.main.arn
}

output "lambda_function_arn" {
  value = aws_lambda_function.main.arn
}

output "sqs_queue_dlq_arn" {
  value = aws_sqs_queue.dlq.arn
}

output "s3_bucket_logs_arn" {
  value = aws_s3_bucket.logs.arn
}

# -------- terraform.tfvars --------

app_name = "devops-genie"