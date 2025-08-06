

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

# VPC Resources
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "public_1" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
}


resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_1.id

 depends_on = [aws_internet_gateway.gw]
}

resource "aws_eip" "nat" {
  vpc = true
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




data "aws_availability_zones" "available" {}



# S3 Buckets
resource "aws_s3_bucket" "upload_bucket" {
  bucket = "${var.app_name}-upload-bucket"
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
    id      = "auto_delete_after_30_days"
    enabled = true

 expiration {
      days = 30
    }
  }
 logging {
    target_bucket = aws_s3_bucket.log_bucket.id
    target_prefix = "log/"
  }
}

resource "aws_s3_bucket" "log_bucket" {
  bucket = "${var.app_name}-log-bucket"

 server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
 sse_algorithm = "AES256"
      }
    }
  }

 lifecycle_rule {
    id      = "auto_delete_after_30_days"
    enabled = true
    expiration {
      days = 30
    }
  }
}



resource "aws_s3_bucket" "processed_bucket" {
  bucket = "${var.app_name}-processed-bucket"
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
    id      = "auto_delete_after_30_days"
    enabled = true
 expiration {
      days = 30
    }
  }
  logging {
    target_bucket = aws_s3_bucket.log_bucket.id
    target_prefix = "log/"
  }

}




# SQS Queue
resource "aws_sqs_queue" "dlq" {
  name = "${var.app_name}-dlq"
}



# Lambda Function
resource "aws_lambda_function" "processor" {
  function_name = "${var.app_name}-processor"
  handler       = "index.handler" # Placeholder, replace with actual handler
 runtime      = "nodejs16.x" # Placeholder, replace with actual runtime
  # filename      = "lambda_function.zip" # Replace with your zipped code or use inline code below

 # Example inline code (replace with your actual code)
 source_code_hash = filebase64sha256("lambda_function.zip")
  filename = "lambda_function.zip"
  # Uncomment for inline code:
  # source_code = <<EOF
  # exports.handler = (event, context) => {
  #   console.log("Event:", JSON.stringify(event, null, 2));
  #   callback(null, "Hello from Lambda!");
  # };
  # EOF
}

resource "null_resource" "zip_lambda_function" {

  provisioner "local-exec" {
 command = "zip -j lambda_function.zip index.js" # Replace index.js with your lambda handler file
  }


}


# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name = "/aws/lambda/${aws_lambda_function.processor.function_name}"
  retention_in_days = 30
}


# S3 Bucket Notification
resource "aws_s3_bucket_notification" "upload_notification" {
  bucket = aws_s3_bucket.upload_bucket.id

 lambda_function {
    lambda_function_arn = aws_lambda_function.processor.arn
    events              = ["s3:ObjectCreated:*"]
  }
}


# Dummy lambda function file - REPLACE THIS WITH YOUR ACTUAL CODE
resource "local_file" "lambda_function_js" {
  content = <<EOF
exports.handler = (event, context, callback) => {
  console.log("Event:", JSON.stringify(event, null, 2));
  callback(null, "Hello from Lambda!");
};
EOF
 filename = "index.js"
}

# -------- outputs.tf --------

output "upload_bucket_name" {
  value = aws_s3_bucket.upload_bucket.id
}

output "processed_bucket_name" {
  value = aws_s3_bucket.processed_bucket.id
}

output "lambda_function_arn" {
  value = aws_lambda_function.processor.arn
}

output "dlq_url" {
  value = aws_sqs_queue.dlq.url
}

# -------- terraform.tfvars --------

app_name = "devops-genie"