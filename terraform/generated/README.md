# Video Platform Infrastructure

This Terraform configuration deploys the core infrastructure for a video platform, including:

* **Video Upload Service:** S3 bucket for storage, API Gateway for secure uploads, and SQS queue for asynchronous processing.
* **Video Playback Service:** CloudFront for content delivery, DynamoDB for metadata storage, and API Gateway for playback requests.
* **Video Processing Pipeline:** SQS queue for task management, Lambda functions for processing, and integration with MediaConvert.

## Deployment

1. **Prerequisites:**
    * AWS account and credentials configured.
    * Terraform installed.

2. **Clone the repository:**