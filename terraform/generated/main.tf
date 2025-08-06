

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

# VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "public_1" {
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

resource "aws_route_table_association" "public_subnet_association" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_eip" "nat_eip" {
  vpc = true
}

resource "aws_nat_gateway" "nat" {
 allocation_id = aws_eip.nat_eip.id
 subnet_id     = aws_subnet.public_1.id
}



# Billing Feature - S3 Bucket
resource "aws_s3_bucket" "billing_bucket" {
  bucket = "${var.app_name}-billing-bucket"

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
    id      = "auto_delete_after_30_days"
    enabled = true
    prefix  = ""

    expiration {
      days = 30
    }
  }

 logging {
    target_bucket = aws_s3_bucket.log_bucket.id
    target_prefix = "billing-bucket-logs/"
 }
}


# Billing Feature - Log Bucket
resource "aws_s3_bucket" "log_bucket" {
  bucket = "${var.app_name}-log-bucket"

  acl    = "log-delivery-write"
  force_destroy = true


 server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
 sse_algorithm     = "AES256"
      }
    }
  }

  lifecycle_rule {
    id      = "auto_delete_after_30_days"
    enabled = true
    prefix  = ""

    expiration {
      days = 30
    }
  }


}

# Billing Feature - Lambda Function and related resources.
resource "aws_lambda_function" "billing_lambda" {
 filename         = "lambda_function.zip" # Replace with an actual zip file or configure inline code
 function_name = "${var.app_name}-billing-lambda"
 handler          = "index.handler"
 runtime          = "nodejs16.x"
 memory_size      = 128
 timeout          = 30


}

resource "aws_cloudwatch_log_group" "billing_lambda_log_group" {
 name = "/aws/lambda/${aws_lambda_function.billing_lambda.function_name}"
 retention_in_days = 30
}

resource "aws_sqs_queue" "billing_dlq" {
  name = "${var.app_name}-billing-dlq"
}

resource "aws_lambda_event_source_mapping" "billing_s3_trigger" {
  batch_size      = 10
  enabled         = true
  event_source_arn = aws_s3_bucket.billing_bucket.arn
  function_name    = aws_lambda_function.billing_lambda.arn


  filter_criteria {
    filters {
      path     = "prefix"
      values = [""] # Trigger on all objects
    }
  }
}

resource "aws_s3_bucket_notification" "billing_bucket_notification" {
  bucket = aws_s3_bucket.billing_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.billing_lambda.arn
    events              = ["s3:ObjectCreated:*"]

    filter_prefix = "" # Notify on all objects
    filter_suffix = ""
  }
}


data "aws_availability_zones" "available" {}

# -------- outputs.tf --------

output "billing_bucket_arn" {
  value = aws_s3_bucket.billing_bucket.arn
}

output "billing_lambda_arn" {
  value = aws_lambda_function.billing_lambda.arn
}

output "billing_dlq_url" {
 value = aws_sqs_queue.billing_dlq.url
}

# -------- terraform.tfvars --------

app_name = "devops-genie"