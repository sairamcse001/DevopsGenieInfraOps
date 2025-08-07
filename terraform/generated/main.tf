

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

# VPC Resources
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

resource "aws_route_table" "public_route" {
  vpc_id = aws_vpc.main.id

 route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

resource "aws_route_table_association" "public_subnet_association" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public_route.id
}



# S3 Buckets
resource "aws_s3_bucket" "main" {
  bucket = "${var.app_name}-video-bucket"

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
    id      = "auto_delete_after_30_days"
    enabled = true
 prefix  = ""

    expiration {
      days = 30
    }
  }

 logging {
    target_bucket = aws_s3_bucket.logs.bucket
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
        sse_algorithm = "AES256"
      }
    }
  }

 lifecycle_rule {
    id      = "auto_delete_after_30_days"
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
resource "aws_lambda_function" "video_processor" {
  function_name = "${var.app_name}-video-processor"
  handler       = "index.handler"
  runtime = "nodejs16.x"
  memory_size = 128
  timeout = 30

  dead_letter_config {
    target_arn = aws_sqs_queue.dlq.arn
  }

 source_code_hash = filebase64sha256("lambda_function_payload.zip")
  filename         = "lambda_function_payload.zip"
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name = "/aws/lambda/${aws_lambda_function.video_processor.function_name}"
  retention_in_days = 30
}

# S3 Bucket Notification
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.main.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.video_processor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix = ".mp4" # Example filter
  }
}

# Dummy zip file for lambda (replace with your actual code)
resource "null_resource" "lambda_zip" {
  provisioner "local-exec" {
    command = "zip lambda_function_payload.zip index.js"
  }
  
 # Create a dummy index.js file for the zip
  provisioner "local-exec" {
    command = "echo 'exports.handler = (event) => { console.log(event); };' > index.js"
 }
}

# Example bucket policy for allowing lambda to be invoked by S3
resource "aws_s3_bucket_policy" "allow_lambda_invoke" {
  bucket = aws_s3_bucket.main.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "s3:PutObject",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
        Resource = "arn:aws:s3:::${aws_s3_bucket.main.id}/*",
        Sid = "AllowLambdaToPutObject"
      }
    ]
  })
}

# -------- outputs.tf --------

output "s3_bucket_arn" {
  value = aws_s3_bucket.main.arn
}

output "lambda_function_arn" {
  value = aws_lambda_function.video_processor.arn
}

output "sqs_queue_url" {
 value = aws_sqs_queue.dlq.url
}

# -------- terraform.tfvars --------

app_name = "devops-genie"