

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

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true

  tags = {
    Name = "main-vpc"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main-igw"
  }
}



resource "aws_subnet" "public_subnet_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
 map_public_ip_on_launch = true
  tags = {
    Name = "public-subnet-a"
  }
}


resource "aws_subnet" "private_subnet_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.101.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "private-subnet-a"
  }
}



resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.main.id

 route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = {
    Name = "public-route-table"
  }
}



resource "aws_route_table_association" "public_subnet_a_association" {
  subnet_id      = aws_subnet.public_subnet_a.id
  route_table_id = aws_route_table.public_route_table.id
}



resource "aws_eip" "nat_eip" {
 vpc = true
}

resource "aws_nat_gateway" "nat" {
 allocation_id = aws_eip.nat_eip.id
 subnet_id     = aws_subnet.public_subnet_a.id
}


resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }


  tags = {
    Name = "private-route-table"
  }
}

resource "aws_route_table_association" "private_subnet_a_association" {
  subnet_id      = aws_subnet.private_subnet_a.id
  route_table_id = aws_route_table.private_route_table.id
}


resource "aws_dynamodb_table" "user_management_table" {
  name         = "user_management_table"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

 tags = {
    Name = "user-management-dynamodb-table"
  }
}

resource "aws_dynamodb_table" "plan_management_table" {
  name         = "plan_management_table"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = {
    Name = "plan_management_dynamodb-table"
  }
}


resource "aws_sqs_queue" "billing_queue" {
 name = "billing_queue"
}

resource "aws_sqs_queue" "billing_dlq" {
  name = "billing_dlq"
}


resource "aws_lambda_function" "billing_lambda" {
 filename      = "dummy_lambda.zip" # Placeholder, replace with your actual Lambda code
 function_name = "billing_lambda"
 handler       = "index.handler" # Adjust based on your Lambda handler
 runtime       = "nodejs16.x"
 role          = aws_iam_role.billing_lambda_role.arn

  vpc_config {
    subnet_ids         = [aws_subnet.private_subnet_a.id]
    security_group_ids = [aws_security_group.billing_lambda_sg.id]
  }
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


resource "aws_security_group" "billing_lambda_sg" {
  name        = "billing_lambda_sg"
  description = "Allow outbound traffic from Lambda"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  tags = {
    Name = "billing_lambda_security_group"
  }
}




resource "aws_s3_bucket" "usage_tracking_bucket" {
  bucket = "usage-tracking-bucket-${random_id.usage_bucket_id.hex}"
  acl    = "private"


  server_side_encryption_configuration {
 rule {
      apply_server_side_encryption_by_default {
 sse_algorithm = "AES256"
      }
 }
  }


 versioning {
    enabled = true
 }

 lifecycle_rule {
    id                                     = "log"
    enabled = true
    expiration {
      days = 30
 }
 }

}



resource "aws_kinesis_firehose_delivery_stream" "usage_tracking_firehose" {
  destination = "s3"
  name        = "usage-tracking-firehose"

  s3_configuration {
    bucket_arn = aws_s3_bucket.usage_tracking_bucket.arn
    role_arn   = aws_iam_role.firehose_role.arn
 }
}



resource "aws_iam_role" "firehose_role" {
  name = "firehose_role"
 assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
 {
        Effect = "Allow",
 Principal = {
          Service = "firehose.amazonaws.com"
 },
 Action = "sts:AssumeRole"
 }
      ]
 })
}



resource "aws_sns_topic" "notification_topic" {
  name = "notification_topic"
}





resource "aws_api_gateway_rest_api" "user_management_api" {
  name        = "user_management_api"
  description = "API Gateway for User Management"
}

resource "random_id" "usage_bucket_id" {
 byte_length = 8
}

# -------- outputs.tf --------

output "user_management_table_arn" {
  value = aws_dynamodb_table.user_management_table.arn
}

output "plan_management_table_arn" {
 value = aws_dynamodb_table.plan_management_table.arn
}

output "billing_queue_url" {
 value = aws_sqs_queue.billing_queue.url
}

output "billing_lambda_arn" {
  value = aws_lambda_function.billing_lambda.arn
}

output "usage_tracking_bucket_arn" {
 value = aws_s3_bucket.usage_tracking_bucket.arn
}

output "notification_topic_arn" {
  value = aws_sns_topic.notification_topic.arn
}

output "user_management_api_id" {
 value = aws_api_gateway_rest_api.user_management_api.id
}


output "vpc_id" {
 value = aws_vpc.main.id
}

output "public_subnet_a_id" {
  value = aws_subnet.public_subnet_a.id
}

output "private_subnet_a_id" {
  value = aws_subnet.private_subnet_a.id
}

# -------- terraform.tfvars --------

