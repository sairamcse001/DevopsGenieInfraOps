

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
    id      = "auto-delete-rule"
    enabled = true
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
    id      = "auto-delete-rule"
    enabled = true
    expiration {
      days = 30
    }
  }
}

resource "aws_sqs_queue" "dlq" {
  name = "${var.app_name}-dlq"
}

resource "aws_lambda_function" "processor" {
  filename         = "lambda_function.zip" # Replace with actual zip or inline code
  function_name    = "${var.app_name}-lambda"
  role             = "arn:aws:iam::YOUR_ACCOUNT_ID:role/lambda_basic_execution" # Placeholder for IAM role
  handler          = "main.lambda_handler" # Adjust based on your handler
  runtime          = "python3.9" # Adjust runtime as needed
  source_code_hash = filebase64sha256("lambda_function.zip")


 dead_letter_config {
    target_arn = aws_sqs_queue.dlq.arn
  }
}




resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name = "/aws/lambda/${aws_lambda_function.processor.function_name}"
  retention_in_days = 30
}



resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.main_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.processor.arn
    events              = ["s3:ObjectCreated:*"]
  }

 depends_on = [aws_lambda_permission.allow_bucket_to_trigger_lambda]

}



resource "aws_lambda_permission" "allow_bucket_to_trigger_lambda" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.processor.function_name
  principal     = "s3.amazonaws.com"
 source_arn = aws_s3_bucket.main_bucket.arn
}



resource "aws_default_vpc" "default_vpc" {}

resource "aws_default_subnet" "default_subnet_a" {}

resource "aws_internet_gateway" "gw" {}

resource "aws_default_route_table" "default_route_table" {}

resource "aws_route" "internet_route" {
  route_table_id         = aws_default_route_table.default_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.gw.id
}

resource "aws_eip" "nat_eip" {}

resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_default_subnet_a.id
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

