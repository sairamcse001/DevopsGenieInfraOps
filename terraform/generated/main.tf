

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

resource "aws_s3_bucket" "main_bucket" {
  bucket = "${var.app_name}-main-bucket"
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
    id      = "remove-old-files"
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
    id      = "remove-old-logs"
 enabled = true
    prefix  = ""
    expiration {
      days = 30
    }
  }
}

resource "aws_lambda_function" "processor" {
 filename      = "lambda_function.zip" # Placeholder, replace as needed.
  function_name = "${var.app_name}-processor"
 handler       = "index.handler"
  runtime        = "nodejs16.x"
 source_code_hash = filebase64sha256("lambda_function.zip") # Placeholder

}


resource "aws_sqs_queue" "dlq" {
  name = "${var.app_name}-dlq"
}


resource "aws_lambda_event_source_mapping" "s3_trigger" {
  function_name = aws_lambda_function.processor.arn
  event_source_arn  = aws_s3_bucket.main_bucket.arn
  batch_size      = 1
  enabled         = true

}

resource "aws_s3_bucket_notification" "bucket_notification" {
 bucket = aws_s3_bucket.main_bucket.id

 lambda_function {
    lambda_function_arn = aws_lambda_function.processor.arn
    events              = ["s3:ObjectCreated:*"]

 }

}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
 name              = "/aws/lambda/${aws_lambda_function.processor.function_name}"
  retention_in_days = 30
}

resource "aws_default_vpc" "default_vpc" {}
resource "aws_default_subnet" "default_subnet_a" {}
resource "aws_internet_gateway" "gw" {}
resource "aws_default_route_table" "rt" {
 default_route_table_id = aws_default_vpc.default_vpc.default_route_table_id
 route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

# -------- outputs.tf --------

output "main_bucket_arn" {
  value = aws_s3_bucket.main_bucket.arn
}

output "lambda_function_arn" {
  value = aws_lambda_function.processor.arn
}

output "dlq_url" {
 value = aws_sqs_queue.dlq.url
}

# -------- terraform.tfvars --------

app_name = "devops-genie"