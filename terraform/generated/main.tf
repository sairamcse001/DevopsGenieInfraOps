

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
  default     = "devops-genie-appname"
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

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_1.id
}

resource "aws_eip" "nat" {
  vpc = true
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




# S3 Bucket (Main)
resource "aws_s3_bucket" "main" {
  bucket = "${var.app_name}-s3-bucket"

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
    target_bucket = aws_s3_bucket.logging.id
    target_prefix = "log/"
  }
}



# S3 Bucket (Logging)
resource "aws_s3_bucket" "logging" {
 bucket = "${var.app_name}-s3-logging-bucket"

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


# SQS Queue (DLQ)
resource "aws_sqs_queue" "dlq" {
  name = "${var.app_name}-dlq"
}

# Lambda Function
resource "aws_lambda_function" "main" {
  function_name = "${var.app_name}-lambda"
  handler       = "index.handler" # Replace with actual handler
  runtime       = "nodejs16.x" # Replace with your runtime
  memory_size   = 128
  timeout       = 30

# Example inline code (replace with zip file if needed)
  inline_code = <<EOF
exports.handler = async (event) => {
  console.log('Event:', JSON.stringify(event));
  return {
    statusCode: 200,
    body: JSON.stringify('Hello from Lambda!'),
  };
};
EOF


 dead_letter_config {
    target_arn = aws_sqs_queue.dlq.arn
  }
}



# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda" {
  name = "/aws/lambda/${aws_lambda_function.main.function_name}"
  retention_in_days = 30
}

# S3 Bucket Notification to trigger Lambda
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.main.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.main.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "" # Optional filter
    filter_suffix       = "" # Optional filter
  }

 depends_on = [aws_lambda_permission.allow_bucket_to_invoke_lambda]
}

# Permissions for S3 to trigger Lambda
resource "aws_lambda_permission" "allow_bucket_to_invoke_lambda" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.main.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.main.arn
}

data "aws_availability_zones" "available" {}

# -------- outputs.tf --------

output "s3_bucket_arn" {
  value = aws_s3_bucket.main.arn
}

output "lambda_function_arn" {
  value = aws_lambda_function.main.arn
}

output "dlq_url" {
 value = aws_sqs_queue.dlq.url
}

# -------- terraform.tfvars --------

app_name = "devops-genie-appname"