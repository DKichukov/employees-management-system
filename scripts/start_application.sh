#!/bin/bash

# Set AWS region (replace 'us-east-1' with your region)
export AWS_REGION=us-east-1

# Ensure required environment variables are set
if [ -z "$ECR_REPOSITORY_URI" ]; then
    echo "Error: ECR_REPOSITORY_URI is not set!" >&2
    exit 1
fi

# Login to AWS ECR (non-interactive)
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REPOSITORY_URI

# Navigate to your application directory (if needed)
cd /home/ec2-user/employee-management-system

# Remove the 'version' line from docker-compose.yml (if it exists)
sed -i '/^version:/d' docker-compose.yml

# Start Docker containers
docker-compose -f docker-compose.yml up -d
