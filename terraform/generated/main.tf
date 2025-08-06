

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

# VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_subnet" "public_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
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

resource "aws_route_table_association" "public_route_table_association_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public_route_table.id
}


# S3 Buckets
resource "aws_s3_bucket" "main" {
  bucket = "${var.app_name}-s3-main"

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
    id                                     = "remove_old_files"
    enabled                               = true
    expiration {
      days = 30
    }
 prefix = ""

  }
 logging {
 target_bucket = aws_s3_bucket.logging.id
 target_prefix = "log/"
  }

}

resource "aws_s3_bucket" "logging" {
  bucket = "${var.app_name}-s3-logging"


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
    id                                     = "remove_old_files"
    enabled                               = true
    expiration {
      days = 30
    }
 prefix = ""

  }


}

# SQS Queue (DLQ)
resource "aws_sqs_queue" "dlq" {
  name = "${var.app_name}-dlq"
}

# Lambda Function

data "archive_file" "lambda_zip" {
    type        = "zip"
    output_path = "/tmp/lambda.zip"
    source_dir  = "./lambda_function/" # Replace with the actual path

}



resource "aws_lambda_function" "main" {
  function_name = "${var.app_name}-lambda"
  handler       = "main.lambda_handler"
  runtime = "python3.9" # Ensure this aligns with the code in lambda_function
  filename         = data.archive_file.lambda_zip.output_path
 source_code_hash = data.archive_file.lambda_zip.output_base64sha256

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

  }
}





# Bucket Policy


resource "aws_s3_bucket_policy" "allow_lambda_trigger" {
  bucket = aws_s3_bucket.main.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
        Action = "s3:GetObject",
        Resource = "arn:aws:s3:::${aws_s3_bucket.main.id}/*"
      },
 {
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
        Action = "s3:PutObject",
 Resource = "arn:aws:s3:::${aws_s3_bucket.logging.id}/*"
      },



            {
        Sid    = "AllowLambdaInvoke",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
        Action = [
          "s3:GetBucketNotification",
          "s3:PutBucketNotification",
                    "s3:ListBucket"
        ],
        Resource = [
                    "arn:aws:s3:::${aws_s3_bucket.main.id}",

        ]
      }
    ]
  })
}

# -------- outputs.tf --------

output "s3_bucket_main_arn" {
  value = aws_s3_bucket.main.arn
}

output "lambda_function_arn" {
 value = aws_lambda_function.main.arn
}

output "dlq_url" {
  value = aws_sqs_queue.dlq.url
}


output "s3_logging_bucket_arn" {
 value = aws_s3_bucket.logging.arn
}

# -------- terraform.tfvars --------

app_name = "devops-genie"