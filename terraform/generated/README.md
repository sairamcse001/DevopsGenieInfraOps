# Video Platform Infrastructure

This Terraform configuration deploys the core infrastructure for a video platform, including:

* **Video Upload Service:** S3 bucket for storage, API Gateway for secure uploads, and SQS queue for asynchronous processing.
* **Video Playback Service:** DynamoDB table for metadata, API Gateway for playback requests, and CloudFront for content delivery.
* **Video Processing Pipeline:** SQS queue for task management, Lambda functions for processing, and MediaConvert for transcoding.

## Deployment

1. **Prerequisites:** Ensure you have AWS credentials configured and Terraform installed.

2. **Clone the repository:**