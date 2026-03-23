output "rds_endpoint" {
  description = "RDS cluster endpoint"
  value       = aws_rds_cluster.main.endpoint
}

output "rds_port" {
  description = "RDS cluster port"
  value       = aws_rds_cluster.main.port
}

output "s3_bucket" {
  description = "S3 bucket for HTML snapshots"
  value       = aws_s3_bucket.snapshots.id
}

output "lambda_role_arn" {
  description = "IAM role ARN for Lambda functions"
  value       = aws_iam_role.lambda.arn
}

output "lambda_security_group_id" {
  description = "Security group ID for Lambda"
  value       = aws_security_group.lambda.id
}

output "lambda_subnet_ids" {
  description = "Subnet IDs for Lambda functions"
  value       = [aws_subnet.private_1.id, aws_subnet.private_2.id]
}
