variable "aws_region" {
  type        = string
  description = "The AWS region to deploy the infrastructure in."
  default     = "us-west-2"
}

variable "video_upload_bucket_name" {
  type        = string
  description = "The name of the S3 bucket for video uploads."
  default     = "video-uploads-${random_id.video_upload.hex}"
}


variable "video_playback_table_name" {
 type = string
 description = "Name of the DynamoDB table for video playback metadata."
 default = "video-playback-metadata"
}