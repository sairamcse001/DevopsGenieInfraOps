

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
  type = string
  description = "Name of the application"
  default = "devops-genie"
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

resource "aws_nat_gateway" "nat" {
  allocation_id = data.aws_eip.nat.id
  subnet_id = aws_subnet.public_1.id
  depends_on = [aws_internet_gateway.gw]
}

data "aws_eip" "nat" {
  vpc = true
}



# S3 Buckets

resource "aws_s3_bucket" "main" {
  bucket = "${var.app_name}-s3-bucket"

 lifecycle_rule {
    id = "expire_objects"
    enabled = true
    expiration {
      days = 30
    }
 }
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
 logging {
    target_bucket = aws_s3_bucket.logs.id
    target_prefix = "log/"
  }
}



resource "aws_s3_bucket" "logs" {
 bucket = "${var.app_name}-s3-logs"


  lifecycle_rule {
    id = "expire_objects"
    enabled = true
    expiration {
      days = 30
    }
  }

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
 filename   = "lambda.zip" # Placeholder, replace as needed
 function_name = "${var.app_name}-lambda"
 handler = "index.handler" # Placeholder, replace as needed
 runtime = "nodejs16.x" # Placeholder, replace as needed

  s3_bucket = aws_s3_bucket.main.id
  s3_key    = "lambda.zip" # Placeholder, replace as needed
 source_code_hash = filebase64sha256("lambda.zip") # Placeholder, replace as needed



}

resource "aws_cloudwatch_log_group" "lambda" {
  name = "/aws/lambda/${aws_lambda_function.main.function_name}"
 retention_in_days = 30

}


resource "aws_lambda_event_source_mapping" "s3_trigger" {
  event_source_arn = aws_s3_bucket.main.arn
  function_name    = aws_lambda_function.main.arn
  enabled = true


}




resource "aws_s3_bucket_notification" "lambda_trigger" {
  bucket = aws_s3_bucket.main.id

 lambda_function {
    lambda_function_arn = aws_lambda_function.main.arn
    events              = ["s3:ObjectCreated:*"]

 filter_prefix = "input/"
 }

 depends_on = [aws_lambda_permission.allow_bucket_to_invoke_lambda]
}

resource "aws_lambda_permission" "allow_bucket_to_invoke_lambda" {
 statement_id  = "AllowExecutionFromS3Bucket"
 action        = "lambda:InvokeFunction"
 function_name = aws_lambda_function.main.function_name
 principal     = "s3.amazonaws.com"
 source_arn    = aws_s3_bucket.main.arn

}


data "aws_availability_zones" "available" {}

resource "aws_default_route_table" "main" {
 default_route {
    cidr_block = "0.0.0.0/0"
 gateway_id = aws_internet_gateway.gw.id
  }

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

output "s3_bucket_logs_arn" {
  value       = aws_s3_bucket.logs.arn

}

# -------- terraform.tfvars --------

app_name = "devops-genie"