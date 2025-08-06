

# -------- provider.tf --------

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }

  required_version = ">= 1.2.0"
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

resource "aws_eip" "nat" {
 vpc = true
}

resource "aws_nat_gateway" "gw" {
 allocation_id = aws_eip.nat.id
 subnet_id     = aws_subnet.public_1.id

 depends_on = [aws_internet_gateway.gw]
}



resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

 route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}


data "aws_availability_zones" "available" {}


# S3 Buckets
resource "aws_s3_bucket" "main" {
  bucket = "${var.app_name}-s3-bucket"


 lifecycle_rule {
    id      = "auto-delete-objects"

    enabled = true

    expiration {
      days = 30
    }
  }

 logging {
    target_bucket = aws_s3_bucket.logs.id
    target_prefix = "log/"
  }
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
}




resource "aws_s3_bucket" "logs" {
  bucket = "${var.app_name}-s3-logs"

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

}


# Lambda Function
resource "aws_lambda_function" "main" {
  function_name = "${var.app_name}-lambda"
  handler       = "index.handler"
  runtime = "nodejs16.x"

  s3_bucket = "devops-genie-lambda-bucket"
  s3_key    = "main.zip"


 dead_letter_config {
    target_arn = aws_sqs_queue.dlq.arn
  }

}




# SQS Queue (DLQ)
resource "aws_sqs_queue" "dlq" {
  name = "${var.app_name}-dlq"
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

 depends_on = [aws_lambda_permission.allow_s3_invoke]
}



# Lambda Permission for S3 Trigger
resource "aws_lambda_permission" "allow_s3_invoke" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.main.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.main.arn
}

# -------- outputs.tf --------

output "s3_bucket_arn" {
  value = aws_s3_bucket.main.arn
}

output "lambda_function_arn" {
  value = aws_lambda_function.main.arn
}

output "sqs_queue_url" {
  value = aws_sqs_queue.dlq.url
}

# -------- terraform.tfvars --------

app_name = "devops-genie"