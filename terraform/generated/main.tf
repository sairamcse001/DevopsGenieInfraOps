

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



# -------- main.tf --------

# User Management Resources

resource "aws_dynamodb_table" "user_management_table" {
  name         = "user_management_table"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "user_id"
  attribute {
    name = "user_id"
    type = "S"
  }
}


resource "aws_api_gateway_rest_api" "user_management_api" {
  name        = "user_management_api"
}


# User Plan Management Resources

resource "aws_dynamodb_table" "user_plan_management_table" {
  name         = "user_plan_management_table"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "plan_id"
  attribute {
    name = "plan_id"
    type = "S"
  }
}

# Billing Resources

resource "aws_lambda_function" "billing_lambda" {
 filename      = "billing_lambda.zip" # Placeholder, no actual file
 function_name = "billing_lambda"
 handler       = "index.handler"
 runtime       = "nodejs16.x"
 role          = aws_iam_role.billing_lambda_role.arn
}

resource "aws_iam_role" "billing_lambda_role" {
  name = "billing_lambda_role"
 assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
 Principal = {
          Service = "lambda.amazonaws.com"
 }
      },
    ]
  })
}

resource "aws_cloudwatch_log_group" "billing_lambda_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.billing_lambda.function_name}"
  retention_in_days = 7
}

# Usage Tracking Resources

resource "aws_kinesis_stream" "usage_tracking_stream" {
  name        = "usage_tracking_stream"
  shard_count = 1
}


# Payment Processing Resources

resource "aws_sqs_queue" "payment_processing_queue" {
 name = "payment_processing_queue"
}



# Search Resources

resource "aws_elasticsearch_domain" "search_domain" {
  domain_name = "search_domain"
 elasticsearch_version = "7.10"
  cluster_config {
    instance_type = "t3.small.elasticsearch"
    instance_count = 1
  }

  ebs_options {
    ebs_enabled = true
    volume_size = 10
  }


  node_to_node_encryption {
 enabled = true
  }


  encryption_at_rest {
 enabled = true
  }
}

# -------- outputs.tf --------

output "user_management_table_arn" {
  value = aws_dynamodb_table.user_management_table.arn
}

output "user_plan_management_table_arn" {
  value = aws_dynamodb_table.user_plan_management_table.arn
}

output "billing_lambda_arn" {
  value = aws_lambda_function.billing_lambda.arn
}

output "usage_tracking_stream_arn" {
 value = aws_kinesis_stream.usage_tracking_stream.arn
}

output "payment_processing_queue_url" {
 value = aws_sqs_queue.payment_processing_queue.url
}


output "search_domain_endpoint" {
  value = aws_elasticsearch_domain.search_domain.endpoint
}

# -------- terraform.tfvars --------

