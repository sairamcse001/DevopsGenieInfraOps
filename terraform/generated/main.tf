

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

resource "aws_subnet" "public_2" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_nat_gateway" "nat" {
  allocation_id = data.aws_eip.nat.id
  subnet_id     = aws_subnet.public_1.id

  depends_on = [aws_internet_gateway.gw]
}

data "aws_eip" "nat" {}

data "aws_availability_zones" "available" {}


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


# S3 Buckets

resource "aws_s3_bucket" "video_storage" {
  bucket = "${var.app_name}-video-storage"
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
    id      = "remove-old-videos"


 enabled = true


    expiration {
      days = 30
    }
  }

 logging {
    target_bucket = aws_s3_bucket.log_bucket.id
    target_prefix = "log/video-storage/"
  }
}



resource "aws_s3_bucket" "log_bucket" {
  bucket = "${var.app_name}-log-bucket"
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

 lifecycle_rule {
    id = "remove-old-logs"


    enabled = true


 expiration {
      days = 30
    }
  }



}



# Lambda Function and Related Resources

resource "aws_lambda_function" "video_processing" {
  filename         = "lambda.zip" # Replace with actual zip file
  function_name    = "${var.app_name}-video-processing"
  role             = "arn:aws:iam::123456789012:role/lambda_basic_execution"  # Replace with an actual IAM role ARN. NO IAM creation in this exercise
  handler          = "index.handler" # Replace with actual handler
  source_code_hash = filebase64sha256("lambda.zip")  # Replace with actual zip file
  runtime          = "nodejs16.x" # Replace with actual runtime
  memory_size      = 128
  timeout          = 30

}



resource "aws_cloudwatch_log_group" "video_processing_log_group" {
 name = "/aws/lambda/${aws_lambda_function.video_processing.function_name}"
  retention_in_days = 30
}


resource "aws_sqs_queue" "dlq" {
  name = "${var.app_name}-dlq"

}



resource "aws_lambda_event_source_mapping" "s3_trigger" {
  event_source_arn = aws_s3_bucket.video_storage.arn
  function_name    = aws_lambda_function.video_processing.arn

}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.video_storage.id

 topic {


    events   = ["s3:ObjectCreated:*"]


    filter_prefix = "" # Trigger on all objects


    filter_suffix = ""


 target {
      id           = "send-to-lambda"


      arn = aws_lambda_function.video_processing.arn



 type = "lambda"
    }
  }


}

# -------- outputs.tf --------

output "video_storage_bucket_arn" {
  value = aws_s3_bucket.video_storage.arn
}

output "video_processing_lambda_arn" {
  value = aws_lambda_function.video_processing.arn
}

output "dlq_url" {
  value = aws_sqs_queue.dlq.url
}

output "log_bucket_arn" {
  value = aws_s3_bucket.log_bucket.arn
}


output "vpc_id" {
  value = aws_vpc.main.id
}

output "subnet_ids" {
 value = [aws_subnet.public_1.id, aws_subnet.public_2.id]
}

# -------- terraform.tfvars --------

app_name = "devops-genie"