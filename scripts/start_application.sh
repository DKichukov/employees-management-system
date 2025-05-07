#!/bin/bash
set -e

echo "Starting application..."

# Get instance region with robust error handling
AWS_REGION=$(curl -s --retry 3 --connect-timeout 1 http://169.254.169.254/latest/meta-data/placement/region || true)

# Fallback methods
if [ -z "$AWS_REGION" ]; then
    AWS_REGION=${AWS_DEFAULT_REGION:-"eu-central-1"}
    echo "WARNING: Using default region: $AWS_REGION"
fi

echo "Using AWS Region: $AWS_REGION"

# Try to determine ECR repository URI
if [ -z "$ECR_REPOSITORY_URI" ]; then
    # Get AWS account ID from metadata
    AWS_ACCOUNT_ID=$(curl -s --retry 3 http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .accountId)

    if [ -z "$AWS_ACCOUNT_ID" ]; then
        echo "ERROR: Could not determine AWS account ID"
        exit 1
    fi

    REPOSITORY_NAME="ems-app"
    ECR_REPOSITORY_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${REPOSITORY_NAME}"
    echo "Determined ECR repository URI: $ECR_REPOSITORY_URI"
fi

echo "Using ECR repository: $ECR_REPOSITORY_URI"

# Set application directory
APP_DIR="/home/ec2-user/employees-management-system"
mkdir -p "$APP_DIR"

# Create .env file
cat > "$APP_DIR/.env" << EOF
ECR_REPOSITORY_URI=$ECR_REPOSITORY_URI
DB_USER=root
DB_PASSWORD=root
DB_NAME=employees_management_system
AWS_REGION=$AWS_REGION
EOF

# Login to ECR with retries
echo "Logging in to ECR..."
for i in {1..3}; do
    if aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ECR_REPOSITORY_URI"; then
        break
    fi
    echo "ECR login attempt $i failed, retrying..."
    sleep 5
done

# Verify login
if ! grep -q "$ECR_REPOSITORY_URI" /root/.docker/config.json; then
    echo "ERROR: Failed to login to ECR"
    exit 1
fi

# Navigate to app directory
cd "$APP_DIR"

# Pull latest image
echo "Pulling latest image from ECR..."
docker pull "$ECR_REPOSITORY_URI:latest" || echo "WARNING: Failed to pull image, will attempt to use cached version"

# Start containers
echo "Starting containers..."
docker compose -f docker-compose.prod.yml up -d

echo "Application started successfully"
