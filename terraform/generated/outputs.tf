output "video_upload_bucket_arn" {
  value = aws_s3_bucket.video_upload_bucket.arn
}

output "video_upload_queue_url" {
 value = aws_sqs_queue.video_upload_queue.url
}



output "video_playback_table_arn" {
 value       = aws_dynamodb_table.video_playback_table.arn
}

output "video_playback_cloudfront_domain" {
 value = aws_cloudfront_distribution.video_playback_distribution.domain_name
}


output "video_processing_queue_url" {
 value = aws_sqs_queue.video_processing_queue.url
}


output "video_processing_lambda_arn" {
 value = aws_lambda_function.video_processing_lambda.arn
}