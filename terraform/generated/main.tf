

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

variable "project_name" {
  type    = string
  default = "default_project"
  description = "Project name used for resource naming."
}

# -------- main.tf --------

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}

resource "aws_subnet" "public_1" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
}

resource "aws_subnet" "public_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]
}


resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.10.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
}

resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.20.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]
}


resource "aws_nat_gateway" "main" {
  subnet_id     = aws_subnet.public_1.id
  allocation_id = data.aws_eip.nat.id

  depends_on = [aws_internet_gateway.main]
}


resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

resource "aws_eip" "nat" {
  vpc = true
}


resource "aws_route_table_association" "public_1" {
 subnet_id      = aws_subnet.public_1.id
 route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_2" {
 subnet_id      = aws_subnet.public_2.id
 route_table_id = aws_route_table.public.id
}

data "aws_availability_zones" "available" {}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block        = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
}

resource "aws_route_table_association" "private_1" {
 subnet_id      = aws_subnet.private_1.id
 route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_2" {
 subnet_id      = aws_subnet.private_2.id
 route_table_id = aws_route_table.private.id
}


resource "aws_dynamodb_table" "user_table" {
  name         = "${var.project_name}-user-table"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "user_id"

  attribute {
    name = "user_id"
    type = "S"
  }
}


resource "aws_s3_bucket" "default" {
  bucket = "${var.project_name}-default-bucket"

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
}

resource "aws_sqs_queue" "default" {
 name = "${var.project_name}-default-queue"
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name = "/aws/lambda/${var.project_name}-default-lambda"
}


resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
        Effect = "Allow",
        Sid    = ""
      }
    ]
  })
}

data "aws_iam_policy_document" "lambda_policy_document" {
  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      aws_cloudwatch_log_group.lambda_log_group.arn
    ]
  }
  statement {
      actions = [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem"
    ]
    resources = [
      aws_dynamodb_table.user_table.arn
    ]
  }
  statement {
      actions = [
 "s3:GetObject",
 "s3:PutObject",
 "s3:ListBucket"
      ]
    resources = [
      aws_s3_bucket.default.arn,
      "${aws_s3_bucket.default.arn}/*"
    ]
  }
  statement {
      actions = [
"sqs:SendMessage",
"sqs:ReceiveMessage",
"sqs:DeleteMessage",
"sqs:GetQueueAttributes"
      ]
    resources = [
      aws_sqs_queue.default.arn
    ]
  }
}

resource "aws_iam_policy" "lambda_policy" {
 name   = "${var.project_name}-lambda-policy"
  policy = data.aws_iam_policy_document.lambda_policy_document.json

}


resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
 policy_arn = aws_iam_policy.lambda_policy.arn
 role       = aws_iam_role.lambda_role.name

}


resource "aws_lambda_function" "default" {
  filename         = "lambda.zip"
  function_name = "${var.project_name}-default-lambda"
  role            = aws_iam_role.lambda_role.arn
  handler         = "main"
  source_code_hash = filebase64sha256("lambda.zip")
  runtime         = "python3.9"
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "lambda.zip"
 source_dir = "./lambda_code"

}

resource "local_file" "lambda_function_file" {
  filename = "./lambda_code/main.py"
 content = <<EOF
def main(event, context):
    print("Hello, world!")
    return {
        'statusCode': 200,
        'body': 'Hello from Lambda!'
    }

EOF

}

# -------- outputs.tf --------

output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = [aws_subnet.public_1.id, aws_subnet.public_2.id]
}

output "private_subnet_ids" {
 value = [aws_subnet.private_1.id, aws_subnet.private_2.id]
}


output "dynamodb_table_arn" {
  value = aws_dynamodb_table.user_table.arn
}

output "s3_bucket_arn" {
 value = aws_s3_bucket.default.arn
}

output "lambda_function_arn" {
 value = aws_lambda_function.default.arn
}

output "sqs_queue_url" {
  value = aws_sqs_queue.default.url
}

# -------- terraform.tfvars --------

