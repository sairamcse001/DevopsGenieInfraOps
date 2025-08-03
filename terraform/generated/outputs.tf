output "video_upload_bucket_arn" {
  value = aws_s3_bucket.video_upload_bucket.arn
}

output "video_processing_queue_url" {
  value = aws_sqs_queue.video_processing_queue.url
}

output "video_upload_api_id" {
 value = aws_api_gateway_rest_api.video_upload_api.id
}



output "video_playback_table_arn" {
 value = aws_dynamodb_table.video_playback_table.arn
}

output "video_playback_api_id" {
 value = aws_api_gateway_rest_api.video_playback_api.id
}

output "cloudfront_distribution_domain" {
 value = aws_cloudfront_distribution.video_playback_distribution.domain_name
}

output "video_processing_lambda_arn" {
  value = aws_lambda_function.video_processing_lambda.arn # Replace with actual Lambda ARN once defined
}