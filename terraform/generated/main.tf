

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

variable "vendor_bucket_name" {
  type        = string
  default     = "vendor-upload-bucket"
  description = "Name of the S3 bucket for vendor uploads"
}

variable "vendor_upload_api_name" {
  type        = string
  default     = "vendor-upload-api"
  description = "Name of the API Gateway API for vendor uploads"
}


variable "upload_queue_name" {
  type        = string
  default     = "vendor-upload-queue"
  description = "Name of the SQS queue for upload notifications"
}

variable "transformation_lambda_name" {
 type = string
 default = "data-transformation-lambda"
 description = "Name of the Lambda function for data transformation"
}

variable "reupload_lambda_name" {
 type = string
 default = "data-reupload-lambda"
 description = "Name of the Lambda function for data re-upload"
}

# -------- main.tf --------

resource "aws_vpc" "main" {
 cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

resource "aws_route_table_association" "public_subnet_association" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public_route_table.id
}




resource "aws_s3_bucket" "vendor_bucket" {
  bucket = var.vendor_bucket_name
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


}


resource "aws_sqs_queue" "upload_queue" {
 name = var.upload_queue_name
}


resource "aws_lambda_function" "transformation_lambda" {
 filename      = "dummy_lambda.zip" # Placeholder, replace in real deployment
 function_name = var.transformation_lambda_name
 handler       = "main"
 runtime       = "python3.9"
 role          = aws_iam_role.lambda_role.arn
 source_code_hash = filebase64sha256("dummy_lambda.zip")
}

resource "aws_iam_role" "lambda_role" {
 name = "lambda_role"
 assume_role_policy = jsonencode({
   Version = "2012-10-17"
   Statement = [
     {
       Action = "sts:AssumeRole"
       Effect = "Allow"
       Principal = {
         Service = "lambda.amazonaws.com"
       }
     },
   ]
 })
}

data "aws_availability_zones" "available" {}


resource "aws_api_gateway_rest_api" "vendor_upload_api" {
 name = var.vendor_upload_api_name
}



resource "aws_lambda_function" "reupload_lambda" {
 filename      = "dummy_lambda.zip" # Placeholder, replace with actual code
 function_name = var.reupload_lambda_name
 handler       = "main"
 runtime       = "python3.9"
 role          = aws_iam_role.lambda_role.arn
 source_code_hash = filebase64sha256("dummy_lambda.zip")
}

# -------- outputs.tf --------

output "vendor_bucket_arn" {
  value = aws_s3_bucket.vendor_bucket.arn
}


output "upload_queue_url" {
 value = aws_sqs_queue.upload_queue.url
}

output "transformation_lambda_arn" {
 value = aws_lambda_function.transformation_lambda.arn
}

output "reupload_lambda_arn" {
 value = aws_lambda_function.reupload_lambda.arn
}

output "vendor_upload_api_id" {
 value = aws_api_gateway_rest_api.vendor_upload_api.id
}

# -------- terraform.tfvars --------

