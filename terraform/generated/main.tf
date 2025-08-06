

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
  default     = "devops-genie"
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

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
 map_public_ip_on_launch = true
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
}


data "aws_availability_zones" "available" {}

resource "aws_eip" "nat_eip" {
 vpc = true
}

resource "aws_nat_gateway" "nat" {
 allocation_id = aws_eip.nat_eip.id
 subnet_id     = aws_subnet.public_1.id

}



resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}



resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id

}

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}


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
    id      = "auto_delete_after_30_days"
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



resource "aws_s3_bucket" "logging" {
  bucket = "${var.app_name}-logging-bucket"
  acl    = "log-delivery-write"


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
}



resource "aws_lambda_function" "example" {
 filename      = "lambda_function.zip"
 function_name = "${var.app_name}-lambda"
 handler       = "index.handler"
 runtime       = "nodejs16.x"


 s3_bucket = "devops-genie-lambda-bucket"
 s3_key    = "lambda_function.zip"

 source_code_hash = filebase64sha256("lambda_function.zip")
}

resource "aws_sqs_queue" "dlq" {
  name = "${var.app_name}-dlq"
}


resource "aws_cloudwatch_log_group" "lambda" {
  name = "/aws/lambda/${aws_lambda_function.example.function_name}"

 retention_in_days = 30

}



resource "aws_s3_bucket_notification" "bucket_notification" {
 bucket = aws_s3_bucket.main.id



 lambda_function {
    lambda_function_arn = aws_lambda_function.example.arn
 events              = ["s3:ObjectCreated:*"]

 filter_prefix = ""
 filter_suffix = ""

  }
 depends_on = [aws_lambda_permission.allow_bucket]
}

resource "aws_lambda_permission" "allow_bucket" {
 statement_id  = "AllowExecutionFromS3Bucket"
 action        = "lambda:InvokeFunction"
 function_name = aws_lambda_function.example.function_name
 principal     = "s3.amazonaws.com"
 source_arn    = aws_s3_bucket.main.arn



}

# -------- outputs.tf --------

output "lambda_function_arn" {
  value = aws_lambda_function.example.arn
}

output "s3_bucket_arn" {
 value = aws_s3_bucket.main.arn
}

output "sqs_queue_url" {
  value = aws_sqs_queue.dlq.url
}

# -------- terraform.tfvars --------

app_name = "devops-genie"