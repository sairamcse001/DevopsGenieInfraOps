variable "aws_region" {
  type    = string
  default = "us-west-2"
  description = "The AWS region to deploy the infrastructure in."
}

variable "video_upload_bucket_name" {
  type = string
  description = "The name of the S3 bucket for video uploads."
}


variable "video_playback_table_name" {
 type = string
 description = "The name of the DynamoDB table for video playback metadata."
}