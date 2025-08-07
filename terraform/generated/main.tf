

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

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
}


resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_eip" "nat_eip" {
  vpc = true
}

resource "aws_nat_gateway" "nat" {
 allocation_id = aws_eip.nat_eip.id
 subnet_id     = aws_subnet.public_1.id
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
    id      = "expire_objects"
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
  bucket = "${var.app_name}-s3-logs"
  acl    = "log-delivery-write"

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

 lifecycle_rule {
    id      = "expire_logs"
    enabled = true

    expiration {
      days = 30
    }
  }
}

resource "aws_lambda_function" "main" {
 filename         = "lambda_function_payload.zip"
 function_name    = "${var.app_name}-lambda"
 role             = "arn:aws:iam::123456789012:role/lambda_basic_execution" # Placeholder - IAM is out of scope
 handler          = "index.handler"
 source_code_hash = filebase64sha256("lambda_function_payload.zip")
 runtime          = "nodejs16.x"

}



resource "aws_sqs_queue" "dlq" {
  name = "${var.app_name}-dlq"
}

resource "aws_lambda_event_source_mapping" "s3_trigger" {
  batch_size      = 10
  enabled         = true
  event_source_arn = aws_s3_bucket.main.arn
  function_name    = aws_lambda_function.main.arn

}


resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.main.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.main.arn
    events              = ["s3:ObjectCreated:*"]
  }

 depends_on = [aws_lambda_permission.allow_bucket_to_invoke_lambda]
}

resource "aws_lambda_permission" "allow_bucket_to_invoke_lambda" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.main.name
  principal     = "s3.amazonaws.com"
 source_arn = aws_s3_bucket.main.arn
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
 name = "/aws/lambda/${aws_lambda_function.main.function_name}"
 retention_in_days = 30
}



data "aws_availability_zones" "available" {}

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

output "s3_bucket_logs" {
  value = aws_s3_bucket.logs.id
}

# -------- terraform.tfvars --------

app_name = "devops-genie-appname"