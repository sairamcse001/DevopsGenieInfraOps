

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
  region = "us-west-2"
}

# -------- variables.tf --------

variable "app_name" {
  type        = string
  description = "Name of the application"
  default     = "devops-genie"
}

# -------- main.tf --------

locals {
  app_name = var.app_name
}



resource "aws_s3_bucket" "main" {
  bucket = "${local.app_name}-main-bucket"

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
    id                                     = "auto-delete-after-30-days"
    enabled                                = true
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
  bucket = "${local.app_name}-logging-bucket"

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
    id                                     = "auto-delete-after-30-days"
    enabled                                = true
    expiration {
 days = 30
    }
 }
}



resource "aws_lambda_function" "example" {
  function_name = "${local.app_name}-lambda"
  handler       = "index.handler"
 runtime      = "nodejs16.x"


  s3_bucket = "devops-genie-lambda-zip"
  s3_key    = "lambda_function_payload.zip"


 dead_letter_config {
    target_arn = aws_sqs_queue.dlq.arn
  }
}




resource "aws_sqs_queue" "dlq" {
  name = "${local.app_name}-dlq"
}


resource "aws_cloudwatch_log_group" "lambda" {
 name = "/aws/lambda/${aws_lambda_function.example.function_name}"
 retention_in_days = 30
}



resource "aws_s3_bucket_notification" "lambda_trigger" {
  bucket = aws_s3_bucket.main.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.example.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix = ".zip"
  }

 depends_on = [aws_lambda_permission.allow_bucket_to_trigger]

}


resource "aws_lambda_permission" "allow_bucket_to_trigger" {
 statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.example.function_name
 principal     = "s3.amazonaws.com"
  source_arn   = aws_s3_bucket.main.arn

}



resource "aws_default_vpc" "default" {}


resource "aws_internet_gateway" "gw" {
  vpc_id = aws_default_vpc.default.id

  tags = {
    Name = "${local.app_name}-igw"
 }
}




resource "aws_subnet" "public_subnet_a" {
  vpc_id                  = aws_default_vpc.default.id
  cidr_block              = "172.31.0.0/20"
  availability_zone       = data.aws_availability_zones.available.names[0]
 map_public_ip_on_launch = true


  tags = {
    Name = "${local.app_name}-public-subnet-a"
 }
}

data "aws_availability_zones" "available" {}

resource "aws_eip" "nat" {
 vpc = true
}




resource "aws_nat_gateway" "gw" {
 allocation_id = aws_eip.nat.id
 subnet_id     = aws_subnet.public_subnet_a.id
}

resource "aws_default_route_table" "default" {
 default_route_table_id = aws_default_vpc.default.default_route_table_id

  route {
    cidr_block = "0.0.0.0/0"
 gateway_id = aws_internet_gateway.gw.id
  }
}


resource "aws_route_table" "private" {
  vpc_id = aws_default_vpc.default.id

 route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.gw.id
  }

 tags = {
    Name = "${local.app_name}-private-route-table"
  }
}

resource "aws_subnet" "private_subnet_a" {
  vpc_id            = aws_default_vpc.default.id
 cidr_block        = "172.31.16.0/20"
 availability_zone = data.aws_availability_zones.available.names[0]


  tags = {
    Name = "${local.app_name}-private-subnet-a"
  }
}

resource "aws_route_table_association" "private_subnet_association" {
 subnet_id      = aws_subnet.private_subnet_a.id
 route_table_id = aws_route_table.private.id
}

# -------- outputs.tf --------

output "s3_bucket_main_arn" {
 value = aws_s3_bucket.main.arn
}

output "s3_bucket_logging_arn" {
 value = aws_s3_bucket.logging.arn
}


output "lambda_function_arn" {
  value = aws_lambda_function.example.arn
}


output "sqs_dlq_arn" {
  value = aws_sqs_queue.dlq.arn
}


output "s3_bucket_main_id" {
  value = aws_s3_bucket.main.id
}

# -------- terraform.tfvars --------

app_name = "devops-genie"