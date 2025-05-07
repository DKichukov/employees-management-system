#!/bin/bash
set -e

echo "Starting application..."

# Get instance region from instance metadata
AWS_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
if [ -z "$AWS_REGION" ]; then
    echo "WARNING: Could not determine AWS region from metadata, defaulting to us-east-1"
    AWS_REGION="us-east-1"
fi

# Validate region
VALID_REGIONS=("us-east-1" "eu-central-1" "us-west-2") # Add your supported regions
if [[ ! " ${VALID_REGIONS[@]} " =~ " ${AWS_REGION} " ]]; then
    echo "ERROR: Unsupported AWS region: ${AWS_REGION}"
    exit 1
fi

echo "Using AWS Region: $AWS_REGION"

# Try to determine the ECR repository URI
if [ -z "$ECR_REPOSITORY_URI" ]; then
    # Get the AWS account ID
    AWS_ACCOUNT_ID=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | grep -oP '(?<="accountId" : ")[^"]*')

    if [ -z "$AWS_ACCOUNT_ID" ]; then
        echo "ERROR: Could not determine AWS account ID from instance metadata"
        exit 1
    fi

    REPOSITORY_NAME="ems-app" # Use your exact ECR repository name
    ECR_REPOSITORY_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${REPOSITORY_NAME}"

    # Verify repository exists
    if ! aws ecr describe-repositories --repository-names "${REPOSITORY_NAME}" --region "${AWS_REGION}" >/dev/null 2>&1; then
        echo "ERROR: ECR repository ${REPOSITORY_NAME} not found in region ${AWS_REGION}"
        exit 1
    fi
fi

echo "Using ECR repository: $ECR_REPOSITORY_URI"

# Create application directory if it doesn't exist
APP_DIR="/home/ec2-user/employees-management-system"
mkdir -p "${APP_DIR}"

# Create .env file for docker-compose
cat > "${APP_DIR}/.env" << EOF
ECR_REPOSITORY_URI=${ECR_REPOSITORY_URI}
DB_USER=root
DB_PASSWORD=root
DB_NAME=employees_management_system
AWS_REGION=${AWS_REGION}
EOF

# Login to AWS ECR
echo "Logging in to ECR..."
aws ecr get-login-password --region "${AWS_REGION}" | docker login --username AWS --password-stdin "${ECR_REPOSITORY_URI}"

# Navigate to application directory
cd "${APP_DIR}"

# Pull latest image
echo "Pulling latest image from ECR..."
docker pull "${ECR_REPOSITORY_URI}:latest" || echo "WARNING: Failed to pull image, will attempt to use cached version"

# Start Docker containers
echo "Starting containers..."
docker compose -f docker-compose.prod.yml up -d

echo "Application started successfully"
