

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

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"
  default     = "10.0.0.0/16"
}


variable "subnet_cidrs" {
 type = list(string)
 description = "List of CIDR blocks for subnets"
 default = ["10.0.1.0/24", "10.0.2.0/24"]

}

variable "lambda_filename" {
  type = string
 description = "Filename of the lambda zip file"
 default = "lambda.zip"
}

# -------- main.tf --------

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
}

resource "aws_subnet" "public" {
  count             = length(var.subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]
}

data "aws_availability_zones" "available" {}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
}




resource "aws_default_route_table" "main" {
  default_route_table_id = aws_vpc.main.default_route_table_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

}


resource "aws_route_table_association" "public" {
  count          = length(var.subnet_cidrs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_default_route_table.main.id
}


resource "aws_s3_bucket" "main" {

 bucket = "${var.app_name}-main-bucket"
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

    id = "auto_delete_after_30_days"

 enabled = true

    expiration {
      days = 30
 }
  }
 logging {
    target_bucket = aws_s3_bucket.logs.id
    target_prefix = "log/"
 }
}

resource "aws_s3_bucket" "logs" {
  bucket = "${var.app_name}-logs-bucket"

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

    id = "auto_delete_after_30_days"

 enabled = true

 expiration {
 days = 30
    }
  }
}


resource "aws_lambda_function" "main" {
 filename         = var.lambda_filename
  function_name = "${var.app_name}-lambda"
 handler       = "index.handler"
  runtime = "nodejs16.x"

 s3_bucket = aws_s3_bucket.main.id
 source_code_hash = filebase64sha256(var.lambda_filename)

}



resource "aws_sqs_queue" "dlq" {
  name = "${var.app_name}-dlq"
}



resource "aws_lambda_event_source_mapping" "s3_trigger" {
  batch_size = 10
  event_source_arn = aws_s3_bucket.main.arn
  function_name = aws_lambda_function.main.arn

  enabled = true
}


resource "aws_cloudwatch_log_group" "lambda" {
  name = "/aws/lambda/${aws_lambda_function.main.function_name}"
  retention_in_days = 30
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.main.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.main.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "input/"
    filter_suffix       = ".json"
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
 value = aws_s3_bucket.logs.arn

}

# -------- terraform.tfvars --------

