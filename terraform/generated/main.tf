

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

# VPC Resources
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "public_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
}

resource "aws_subnet" "public_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]
}


resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

}



resource "aws_eip" "nat_eip" {
 vpc = true
}

resource "aws_nat_gateway" "gw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_1.id

  depends_on = [aws_internet_gateway.gw]
}

resource "aws_route_table" "public" {


  vpc_id = aws_vpc.main.id


  route {
    cidr_block        = "0.0.0.0/0"
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
  bucket = "${var.app_name}-bucket"

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
    id      = "auto_delete"
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
  bucket = "${var.app_name}-logs-bucket"



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

# Lambda Function and Related Resources
resource "aws_lambda_function" "main" {
  filename         = "lambda.zip" # Replace with your Lambda zip file
  function_name = "${var.app_name}-lambda"
  handler         = "index.handler"
  runtime = "nodejs16.x" # Or any runtime supported by AWS Lambda
  source_code_hash = filebase64sha256("lambda.zip") # Generate this after creating your lambda.zip


 memory_size = 128
  timeout = 30

 dead_letter_config {
    target_arn = aws_sqs_queue.dlq.arn
  }
}

resource "aws_cloudwatch_log_group" "lambda" {
  name = "/aws/lambda/${aws_lambda_function.main.function_name}"
 retention_in_days = 30
}


resource "aws_sqs_queue" "dlq" {
  name = "${var.app_name}-dlq"

}



# S3 Bucket Notification
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.main.id

  lambda_function {
 lambda_function_arn = aws_lambda_function.main.arn
    events              = ["s3:ObjectCreated:*"]

 filter_suffix = ".zip" # Optional filter to specify file types


  }

 depends_on = [aws_lambda_permission.allow_bucket_to_trigger_lambda]
}



resource "aws_lambda_permission" "allow_bucket_to_trigger_lambda" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.main.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.main.arn
}

# -------- outputs.tf --------

output "s3_bucket_main_arn" {
  value = aws_s3_bucket.main.arn
}

output "lambda_function_arn" {
  value = aws_lambda_function.main.arn
}

output "sqs_dlq_url" {
 value = aws_sqs_queue.dlq.url
}

output "s3_bucket_logs_arn" {
  value = aws_s3_bucket.logs.arn
}

# -------- terraform.tfvars --------

