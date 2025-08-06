

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

variable "appname" {
  type        = string
  description = "Name of the application"
  default     = "devops-genie"
}

# -------- main.tf --------

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "public_1" {
  cidr_block        = "10.0.1.0/24"
  vpc_id            = aws_vpc.main.id
  availability_zone = data.aws_availability_zones.available.names[0]
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_1.id

  depends_on = [aws_internet_gateway.gw]
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



resource "aws_s3_bucket" "upload_bucket" {
  bucket = "${var.appname}-upload-bucket"

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
    id      = "delete_after_30_days"
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

resource "aws_s3_bucket" "processed_bucket" {
  bucket = "${var.appname}-processed-bucket"
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
    id      = "delete_after_30_days"
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
  bucket = "${var.appname}-log-bucket"
  acl    = "log-delivery-write"
  force_destroy = true
}

resource "aws_lambda_function" "processor_lambda" {
  filename      = "lambda_function.zip" # Replace with your lambda zip file
  function_name = "${var.appname}-processor-lambda"
  handler       = "index.handler" # Replace with your lambda handler
  runtime       = "nodejs16.x"
  memory_size   = 128
  timeout       = 30

  s3_bucket = "your-s3-bucket-for-lambda-code" # Replace with your bucket for the zip file
  s3_key    = "lambda_function.zip"

 dead_letter_config {
    target_arn = aws_sqs_queue.dlq.arn
  }

}


resource "aws_cloudwatch_log_group" "processor_lambda_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.processor_lambda.function_name}"
  retention_in_days = 30
}

resource "aws_sqs_queue" "dlq" {
 name = "${var.appname}-dlq"
}


resource "aws_s3_bucket_notification" "upload_notification" {
  bucket = aws_s3_bucket.upload_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.processor_lambda.arn
    events              = ["s3:ObjectCreated:*"]
 filter_prefix = ""
  }
 depends_on = [aws_lambda_permission.allow_bucket_to_trigger_lambda]
}


resource "aws_lambda_permission" "allow_bucket_to_trigger_lambda" {
 statement_id  = "AllowExecutionFromS3Bucket"
 action        = "lambda:InvokeFunction"
 function_name = aws_lambda_function.processor_lambda.function_name
 principal     = "s3.amazonaws.com"
 source_arn    = aws_s3_bucket.upload_bucket.arn
}

# -------- outputs.tf --------

output "upload_bucket_name" {
  value = aws_s3_bucket.upload_bucket.id
}

output "processed_bucket_name" {
  value = aws_s3_bucket.processed_bucket.id
}

output "lambda_function_arn" {
  value = aws_lambda_function.processor_lambda.arn
}

output "dlq_url" {
  value = aws_sqs_queue.dlq.id
}

# -------- terraform.tfvars --------

appname = "devops-genie"