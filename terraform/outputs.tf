output "ecr_repository_url" {
  description = "The URL of the ECR repository"
  value       = aws_ecr_repository.app_ecr_repo.repository_url
}

output "ec2_instance_public_dns" {
  description = "The public DNS name of the EC2 instance"
  value       = aws_instance.app_instance.public_dns
}

output "ec2_instance_public_ip" {
  description = "The public IP of the EC2 instance"
  value       = aws_instance.app_instance.public_ip
}

output "application_url" {
  description = "The URL to access the application"
  value       = "http://${aws_instance.app_instance.public_dns}:8080"
}

# output "github_connection_status" {
#   description = "Status of the GitHub connection (requires manual approval in the AWS console)"
#   value       = aws_codestarconnections_connection.github.status
# }

output "github_connection_arn" {
  description = "ARN of the GitHub connection"
  value       = aws_codestarconnections_connection.github.arn
}
