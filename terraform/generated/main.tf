

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

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
}


resource "aws_default_route_table" "main" {
  default_route_table_id = aws_vpc.main.default_route_table_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

resource "aws_route_table_association" "a" {
 subnet_id      = aws_subnet.public_1.id
 route_table_id = aws_default_route_table.main.id
}

data "aws_availability_zones" "available" {}



# S3 Buckets

resource "aws_s3_bucket" "main" {
  bucket = "${var.app_name}-storage"
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
    id = "auto_delete"
 enabled = true
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
 bucket = "${var.app_name}-logs"
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
}


# SQS Queue (DLQ)

resource "aws_sqs_queue" "dlq" {
  name = "${var.app_name}-dlq"
}

# Lambda Function

resource "aws_lambda_function" "main" {
  filename      = "lambda_function.zip" # Replace with your zip file
  function_name = "${var.app_name}-lambda"
  handler       = "index.handler" # Replace with your handler
  runtime       = "nodejs16.x"
  source_code_hash = filebase64sha256("lambda_function.zip")

  s3_bucket = aws_s3_bucket.main.id
  s3_key = "lambda_function.zip"


  dead_letter_config {
    target_arn = aws_sqs_queue.dlq.arn
  }
}



# CloudWatch Log Group for Lambda

resource "aws_cloudwatch_log_group" "lambda" {
  name = "/aws/lambda/${aws_lambda_function.main.function_name}"
  retention_in_days = 30
}



# S3 Bucket Notification

resource "aws_s3_bucket_notification" "lambda_trigger" {
  bucket = aws_s3_bucket.main.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.main.arn
    events              = ["s3:ObjectCreated:*"]

  }
}


# Dummy Lambda Function Code (replace with your actual code)
data "archive_file" "lambda_zip" {
 type        = "zip"
 output_path = "lambda_function.zip"
 source_dir  = "./lambda_code" # Directory containing your lambda code
}

resource "local_file" "lambda_code_file" {
  content  = <<EOF
exports.handler = async (event) => {
  const response = {
    statusCode: 200,
    body: JSON.stringify('Hello from Lambda!'),
  };
  return response;
};
EOF
 filename = "./lambda_code/index.js"

}

# -------- outputs.tf --------

output "s3_bucket_main_arn" {
  value = aws_s3_bucket.main.arn
}

output "lambda_function_arn" {
  value = aws_lambda_function.main.arn
}

output "sqs_queue_dlq_arn" {
  value       = aws_sqs_queue.dlq.arn
}


output "s3_bucket_logs_arn" {
 value = aws_s3_bucket.logs.arn
}

# -------- terraform.tfvars --------

app_name = "devops-genie"