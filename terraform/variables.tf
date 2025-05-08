variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "app_name" {
  description = "Name of the application"
  default     = "ems-app"
}

variable "environment" {
  description = "Deployment environment"
  default     = "dev"
}

variable "instance_type" {
  description = "EC2 instance type"
  default     = "t2.micro"
}

variable "ssh_key_name" {
  description = "SSH key name for EC2 instance"
  default     = "my-key-pair"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for subnet"
  default     = "10.0.1.0/24"
}

variable "repo_url" {
  description = "GitHub repository URL"
  type        = string
}

variable "github_token" {
  description = "GitHub OAuth token"
  type        = string
  sensitive   = true
}

variable "github_branch" {
  description = "The GitHub branch to use for the pipeline source"
  type        = string
  default     = "master"
}
