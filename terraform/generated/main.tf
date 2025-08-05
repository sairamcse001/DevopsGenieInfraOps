

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



# -------- main.tf --------

resource "aws_s3_bucket" "file_upload_bucket" {
  bucket = "file-upload-bucket-${random_id.bucket_suffix.hex}"
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

 lifecycle {
    prevent_destroy = false
 }
}

resource "random_id" "bucket_suffix" {
  byte_length = 8
}


resource "aws_iam_user_group" "file_upload_users" {
  name = "file-upload-users"
}


resource "aws_iam_policy" "file_upload_policy" {

 name = "file-upload-policy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "AllowS3ListBucket",
        Effect = "Allow",
        Action = "s3:ListBucket",
        Resource = aws_s3_bucket.file_upload_bucket.arn

      },
 {
        Sid    = "AllowS3ObjectActions",
        Effect = "Allow",
        Action = [
 "s3:PutObject",
 "s3:GetObject",
 "s3:DeleteObject",
 "s3:GetObjectAcl",
 "s3:PutObjectAcl"


        ],
 Resource = [
          aws_s3_bucket.file_upload_bucket.arn,
          "${aws_s3_bucket.file_upload_bucket.arn}/*"
 ]
      }
    ]
  })
}

resource "aws_iam_group_policy_attachment" "file_upload_group_policy" {
 group = aws_iam_user_group.file_upload_users.name
  policy_arn = aws_iam_policy.file_upload_policy.arn
}

# -------- outputs.tf --------

output "s3_bucket_arn" {
  value = aws_s3_bucket.file_upload_bucket.arn
}

output "s3_bucket_id" {
 value = aws_s3_bucket.file_upload_bucket.id
}

output "iam_group_id" {
 value = aws_iam_user_group.file_upload_users.id
}
output "iam_policy_arn" {
  value       = aws_iam_policy.file_upload_policy.arn

}

# -------- terraform.tfvars --------

