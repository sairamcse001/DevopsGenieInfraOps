

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

variable "dynamodb_table_name" {
  type        = string
  default     = "user_management_table"
  description = "Name of the DynamoDB table for user management"
}

variable "api_gateway_name" {
  type        = string
  default     = "user_management_api"
  description = "Name of the API Gateway for user management"
}

variable "rds_instance_identifier" {
  type        = string
  default     = "subscription_management_db"
  description = "Identifier for the RDS instance"
}

variable "lambda_billing_function_name" {
 type = string
 default = "billing_lambda_function"
 description = "Name of the billing lambda function"
}

variable "kinesis_stream_name" {
 type = string
 default = "usage_tracking_stream"
 description = "Name for the Kinesis data stream"
}


variable "s3_bucket_name" {
  type        = string
  default     = "usage_tracking_bucket"
  description = "Name of the S3 bucket for usage tracking"
}


variable "opensearch_domain_name" {
  type        = string
  default     = "search_domain"
  description = "Name of the OpenSearch domain"
}

variable "ec2_payment_integration_instance_name" {
 type = string
 default = "payment_integration_instance"
 description = "Name for the EC2 payment integration instance"
}

variable "ec2_reward_integration_instance_name" {
 type = string
 default = "reward_integration_instance"
 description = "Name for the EC2 reward integration instance"
}

# -------- main.tf --------

resource "aws_dynamodb_table" "user_management" {
 name = var.dynamodb_table_name
 billing_mode = "PAY_PER_REQUEST"
 hash_key = "userId"
 attribute {
   name = "userId"
   type = "S"
 }
}


resource "aws_api_gateway_rest_api" "user_management" {
 name = var.api_gateway_name
}



resource "aws_db_instance" "subscription_management" {
  allocated_storage      = 20
  db_instance_identifier = var.rds_instance_identifier
  engine                 = "postgres"
  engine_version         = "14"
  instance_class         = "db.t3.micro"
  username               = "admin"
  password               = "password" # In real scenarios, do not hardcode! Use secure methods for generating and managing passwords.
  skip_final_snapshot    = true
}



resource "aws_lambda_function" "billing_function" {
 filename         = "lambda_function_payload.zip" # Placeholder, replace with actual zip file in real usage
 function_name = var.lambda_billing_function_name
 handler          = "index.handler" # Adjust if needed
 runtime          = "nodejs16.x"
 role            = aws_iam_role.lambda_execution_role.arn

 source_code_hash = filebase64sha256("lambda_function_payload.zip") # Update for your actual function code

}

resource "aws_iam_role" "lambda_execution_role" {
  name = "lambda_execution_role"
  assume_role_policy = jsonencode({
 Version = "2012-10-17"
 Statement = [
 {
 Action = "sts:AssumeRole"
 Effect = "Allow"
 Principal = {
 Service = "lambda.amazonaws.com"
 }
 Sid    = ""
 }
 ]
  })
}


resource "aws_kinesis_stream" "usage_tracking" {
 name        = var.kinesis_stream_name
 shard_count = 1
}



resource "aws_s3_bucket" "usage_tracking" {
  bucket = var.s3_bucket_name
}



resource "aws_opensearch_domain" "search" {
 domain_name = var.opensearch_domain_name

  cluster_config {
    instance_type = "t3.small.search"
    instance_count = 1
  }

  engine_version = "OpenSearch_2.0"

  ebs_options {
    ebs_enabled = true
 volume_size = 10
  }


}



resource "aws_instance" "payment_integration" {
 ami           = data.aws_ami.amazon_linux_2.id
 instance_type = "t3.micro"
 key_name = "mykey" # Replace with your key

 tags = {
   Name = var.ec2_payment_integration_instance_name
 }
}
data "aws_ami" "amazon_linux_2" {

 most_recent = true

 owners      = ["amazon"]

 filter {
   name   = "name"
   values = ["amzn2-ami-hvm*"]
 }


}



resource "aws_instance" "reward_integration" {
  ami           = data.aws_ami.amazon_linux_2.id
  instance_type = "t3.micro"
 key_name = "mykey" # Replace with your key
 tags = {
 Name = var.ec2_reward_integration_instance_name
 }

}

# -------- outputs.tf --------

output "dynamodb_table_arn" {
 value = aws_dynamodb_table.user_management.arn
}


output "api_gateway_id" {
 value = aws_api_gateway_rest_api.user_management.id
}



output "rds_endpoint" {
 value = aws_db_instance.subscription_management.endpoint
}

output "lambda_function_arn" {
 value = aws_lambda_function.billing_function.arn
}



output "kinesis_stream_arn" {
  value = aws_kinesis_stream.usage_tracking.arn
}




output "s3_bucket_arn" {
 value = aws_s3_bucket.usage_tracking.arn
}


output "opensearch_domain_endpoint" {
  value = aws_opensearch_domain.search.endpoint
}




output "ec2_payment_integration_public_ip" {
 value = aws_instance.payment_integration.public_ip
}


output "ec2_reward_integration_public_ip" {
 value = aws_instance.reward_integration.public_ip
}

# -------- terraform.tfvars --------

