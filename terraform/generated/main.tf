

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
    id      = "auto-delete-objects"
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
    id      = "auto-delete-objects"
    enabled = true
 prefix  = ""

    expiration {
      days = 30
    }
  }
}




resource "aws_lambda_function" "main_lambda" {
  function_name = "${var.app_name}-lambda"
  handler       = "index.handler" # Placeholder
  runtime       = "nodejs16.x"
  filename      = "lambda_function.zip" # Placeholder
  memory_size = 128
  timeout = 30


  s3_bucket = "my-lambda-bucket"
  s3_key    = "my-lambda-key"


  source_code_hash = filebase64sha256("lambda_function.zip") # Placeholder, replace with real zip and path

}


resource "aws_sqs_queue" "dlq" {
  name = "${var.app_name}-dlq"
}


resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.main_lambda.function_name}"
  retention_in_days = 30
}



resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.main_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.main_lambda.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = ""
 filter_suffix = ""
  }
}




resource "aws_default_vpc" "default_vpc" {}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_default_vpc.default_vpc.id

  tags = {
    Name = "${var.app_name}-igw"
  }
}

# -------- outputs.tf --------

output "main_bucket_arn" {
  value = aws_s3_bucket.main_bucket.arn
}

output "lambda_arn" {
  value = aws_lambda_function.main_lambda.arn
}

# -------- terraform.tfvars --------

app_name = "devops-genie"