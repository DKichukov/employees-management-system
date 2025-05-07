#!/bin/bash
set -e

echo "Starting application..."

# Get instance region from instance metadata
AWS_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
if [ -z "$AWS_REGION" ]; then
    # Default to us-east-1 if we can't determine the region
    AWS_REGION="us-east-1"
fi
echo "Using AWS Region: $AWS_REGION"

# Try to determine the ECR repository URI dynamically if not set
if [ -z "$ECR_REPOSITORY_URI" ]; then
    # Get the AWS account ID
    AWS_ACCOUNT_ID=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | grep -oP '(?<="accountId" : ")[^"]*')

    # If we get the account ID, try to construct the ECR URI
    if [ ! -z "$AWS_ACCOUNT_ID" ]; then
        # Try to find the repository name from the CodeDeploy deployment-group
        DEPLOYMENT_GROUP_NAME=$(cat /opt/codedeploy-agent/deployment-root/deployment-instructions/*/deployment-group-id 2>/dev/null || echo "")
        REPOSITORY_NAME=$(echo "$DEPLOYMENT_GROUP_NAME" | grep -oP '(?<=-)[^-]*$' 2>/dev/null || echo "ems-app")

        # Construct ECR repository URI
        ECR_REPOSITORY_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${REPOSITORY_NAME}"
        echo "Determined ECR repository URI: $ECR_REPOSITORY_URI"
    else
        echo "Could not determine AWS account ID. Please set ECR_REPOSITORY_URI environment variable."
        exit 1
    fi
fi

echo "Using ECR repository: $ECR_REPOSITORY_URI"

# Create .env file for docker-compose
cat > /home/ec2-user/employees-management-system/.env << EOF
ECR_REPOSITORY_URI=$ECR_REPOSITORY_URI
DB_USER=root
DB_PASSWORD=root
DB_NAME=employees_management_system
EOF

# Login to AWS ECR
echo "Logging in to ECR..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REPOSITORY_URI

# Navigate to application directory
cd /home/ec2-user/employees-management-system

# Check if we need to pull the image first
echo "Pulling latest image from ECR..."
docker pull $ECR_REPOSITORY_URI:latest || echo "Failed to pull image, will attempt to use cached version"

# Start Docker containers
echo "Starting containers..."
docker compose -f docker-compose.prod.yml up -d

echo "Application started successfully"
