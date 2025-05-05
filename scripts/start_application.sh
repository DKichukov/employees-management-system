#!/bin/bash
echo "Starting application..."
cd /home/ec2-user/employee-management-system

# Get the ECR repository URI
AWS_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Login to ECR
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# Start the containers using docker-compose
docker-compose -f docker-compose.prod.yml up -d

echo "Application started successfully"
