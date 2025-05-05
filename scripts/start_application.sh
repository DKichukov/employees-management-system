#!/bin/bash
echo "Starting application..."
cd /home/ec2-user/employee-management-system || exit 1

# Get AWS region from instance metadata
AWS_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)

# Get ECR repository URI from environment variables (set by CodeDeploy)
ECR_REPOSITORY_URI=${ECR_REPOSITORY_URI}
if [ -z "$ECR_REPOSITORY_URI" ]; then
    echo "ERROR: ECR_REPOSITORY_URI environment variable not set"
    exit 1
fi

# Login to ECR
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ECR_REPOSITORY_URI" || {
    echo "ERROR: Failed to login to ECR"
    exit 1
}

# Start the containers
docker compose -f docker-compose.yml up -d || {
    echo "ERROR: Failed to start containers"
    exit 1
}

echo "Application started successfully"
