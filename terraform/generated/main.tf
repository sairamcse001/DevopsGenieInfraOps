

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

variable "project_name" {
  type        = string
  description = "Project name used for resource naming"
  default     = "ride-sharing-app"
}

# -------- main.tf --------

# VPC and Networking

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "public_subnet_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
 map_public_ip_on_launch = true
}

resource "aws_subnet" "private_subnet_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
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
}

resource "aws_route_table_association" "private_subnet_association" {
  subnet_id      = aws_subnet.private_subnet_a.id
  route_table_id = aws_route_table.private_route_table.id
}

data "aws_availability_zones" "available" {}


# Search Service

resource "aws_lambda_function" "search_service_lambda" {
  function_name = "${var.project_name}-search-service"
  handler       = "index.handler"
  runtime       = "nodejs16.x"
  role          = aws_iam_role.lambda_exec_role.arn
  memory_size = 128
 timeout = 30

  source_code_hash = data.archive_file.search_lambda_zip.output_base64sha256
}

data "archive_file" "search_lambda_zip" {
  type        = "zip"
  source_dir  = "./modules/search_service_lambda"
 output_path = "search_lambda.zip"
}


resource "aws_api_gateway_rest_api" "search_api" {
  name        = "${var.project_name}-search-api"
}



# Dummy Lambda function code
resource "null_resource" "create_dummy_lambda_code" {

  provisioner "local-exec" {
    command = "mkdir -p modules/search_service_lambda && echo 'exports.handler = async (event) => { return {statusCode: 200, body: JSON.stringify({message: \"Hello from search service\"})}};' > modules/search_service_lambda/index.js"
  }

}

resource "aws_iam_role" "lambda_exec_role" {
  name = "${var.project_name}-lambda-role"

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


resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
 role       = aws_iam_role.lambda_exec_role.name
 policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_cloudwatch_log_group" "search_lambda_log_group" {
  name = "/aws/lambda/${aws_lambda_function.search_service_lambda.function_name}"
 retention_in_days = 7
}

# -------- outputs.tf --------

output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_id" {
 value = aws_subnet.public_subnet_a.id
}

output "private_subnet_id" {
  value = aws_subnet.private_subnet_a.id
}

output "search_lambda_arn" {
  value = aws_lambda_function.search_service_lambda.arn
}

output "search_api_id" {
 value = aws_api_gateway_rest_api.search_api.id
}

# -------- terraform.tfvars --------

