

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

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "public_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_1.id

  depends_on = [aws_internet_gateway.main]
}

resource "aws_eip" "nat" {
  vpc = true
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


resource "aws_s3_bucket" "main" {
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
    id      = "auto_delete_after_30_days"
    enabled = true
    expiration {
      days = 30
    }
  }
 logging {
    target_bucket = aws_s3_bucket.logging.id
    target_prefix = "log/"
  }

}

resource "aws_s3_bucket" "logging" {
  bucket = "${var.app_name}-logging-bucket"


 server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
}


resource "aws_lambda_function" "main" {
  filename         = "lambda.zip" # Replace with your lambda zip file
  function_name = "${var.app_name}-lambda"
  handler        = "index.handler" # Replace with your handler
  runtime         = "nodejs16.x"   # Replace with your runtime
  memory_size = 128
  timeout = 300

 s3_bucket = aws_s3_bucket.main.id # For deployment from S3
 s3_key    = "lambda.zip" # For deployment from S3

  dead_letter_config {
    target_arn = aws_sqs_queue.dlq.arn
  }
}


resource "aws_sqs_queue" "dlq" {
  name = "${var.app_name}-dlq"
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
  }

 depends_on = [aws_lambda_permission.allow_s3_invoke]
}



resource "aws_lambda_permission" "allow_s3_invoke" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.main.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.main.arn
}



data "aws_availability_zones" "available" {}

# -------- outputs.tf --------

output "lambda_function_arn" {
  value = aws_lambda_function.main.arn
}

output "s3_bucket_arn" {
  value = aws_s3_bucket.main.arn
}

output "s3_bucket_logging_arn" {
  value       = aws_s3_bucket.logging.arn
}
output "sqs_dlq_arn" {
 value = aws_sqs_queue.dlq.arn
}

# -------- terraform.tfvars --------

app_name = "devops-genie"