#!/bin/bash
set -e

echo "Starting application..."

# Hardcode your ECR details to ensure reliability
HARDCODED_ECR_REPOSITORY_URI="565393040546.dkr.ecr.eu-central-1.amazonaws.com/ems-app"
HARDCODED_REGION="eu-central-1"

# Try to get instance region with robust error handling
AWS_REGION=""
if command -v curl &>/dev/null; then
    # Check if IMDSv2 token is required
    TOKEN=$(curl -s -f -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null || echo "")

    if [ -n "$TOKEN" ]; then
        # Use IMDSv2
        AWS_REGION=$(curl -s -f -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null || echo "")
    else
        # Try IMDSv1 as fallback
        AWS_REGION=$(curl -s -f http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null || echo "")
    fi
fi

# If still empty, try AWS CLI config
if [ -z "$AWS_REGION" ]; then
    AWS_REGION=$(aws configure get region 2>/dev/null || echo "")
fi

# If still empty, use environment variable
if [ -z "$AWS_REGION" ]; then
    AWS_REGION=${AWS_DEFAULT_REGION:-$HARDCODED_REGION}
    echo "WARNING: Using fallback region: $AWS_REGION"
fi

echo "Using AWS Region: $AWS_REGION"

# Set ECR repository URI
if [ -z "$ECR_REPOSITORY_URI" ]; then
    # First try to build it dynamically
    AWS_ACCOUNT_ID=""

    # Try to get account ID using IMDSv2 if token exists
    if [ -n "$TOKEN" ]; then
        AWS_ACCOUNT_ID=$(curl -s -f -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/dynamic/instance-identity/document 2>/dev/null | grep -o '"accountId" : "[^"]*' | cut -d'"' -f4 || echo "")
    fi

    # If account ID is still empty, try AWS CLI
    if [ -z "$AWS_ACCOUNT_ID" ]; then
        AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
    fi

    # If we have account ID, construct the URI
    if [ -n "$AWS_ACCOUNT_ID" ]; then
        REPOSITORY_NAME="ems-app"
        ECR_REPOSITORY_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${REPOSITORY_NAME}"
        echo "Dynamically determined ECR repository URI: $ECR_REPOSITORY_URI"
    else
        # Use hardcoded URI as fallback
        ECR_REPOSITORY_URI="$HARDCODED_ECR_REPOSITORY_URI"
        echo "Using hardcoded ECR repository URI"
    fi
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

# Create docker-compose file if it doesn't exist
if [ ! -f "$APP_DIR/docker-compose.prod.yml" ]; then
    echo "Creating docker-compose.prod.yml file..."
    cat > "$APP_DIR/docker-compose.prod.yml" << 'EOF'
services:
  postgres:
    image: postgres:13-alpine
    container_name: ems-db
    ports:
      - "5432:5432"
    environment:
      POSTGRES_USER: ${DB_USER:-root}
      POSTGRES_PASSWORD: ${DB_PASSWORD:-root}
      POSTGRES_DB: ${DB_NAME:-employees_management_system}
    volumes:
      - postgres-data:/var/lib/postgresql/data
    healthcheck:
      test: [ "CMD-SHELL", "pg_isready -U ${DB_USER:-root} -d ${DB_NAME:-employees_management_system}" ]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: unless-stopped
    networks:
      - app-network

  app:
    image: ${ECR_REPOSITORY_URI}:latest
    container_name: ems-app
    ports:
      - "8080:8080"
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      SPRING_DATASOURCE_URL: jdbc:postgresql://postgres:5432/${DB_NAME:-employees_management_system}
      SPRING_DATASOURCE_USERNAME: ${DB_USER:-root}
      SPRING_DATASOURCE_PASSWORD: ${DB_PASSWORD:-root}
      SPRING_JPA_HIBERNATE_DDL_AUTO: update
      SPRING_JPA_PROPERTIES_HIBERNATE_DIALECT: org.hibernate.dialect.PostgreSQLDialect
      AWS_REGION: ${AWS_REGION}
    restart: unless-stopped
    networks:
      - app-network

volumes:
  postgres-data:

networks:
  app-network:
EOF
fi

# Login to ECR with error handling
echo "Logging in to ECR..."
for i in {1..3}; do
    if aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin $(echo "$ECR_REPOSITORY_URI" | cut -d'/' -f1) 2>/dev/null; then
        echo "Successfully logged in to ECR"
        break
    fi

    if [ $i -eq 3 ]; then
        echo "WARNING: Failed to log in to ECR after 3 attempts. Continuing anyway..."
    else
        echo "ECR login attempt $i failed, retrying in 5 seconds..."
        sleep 5
    fi
done

# Navigate to app directory
cd "$APP_DIR"

# Pull latest image with error handling
echo "Pulling latest image from ECR..."
if docker pull "$ECR_REPOSITORY_URI:latest"; then
    echo "Successfully pulled latest image"
else
    echo "WARNING: Failed to pull image, will attempt to use cached version"

    # Check if image exists locally
    if ! docker image inspect "$ECR_REPOSITORY_URI:latest" &>/dev/null; then
        echo "ERROR: Image does not exist locally and could not be pulled"
        exit 1
    fi
fi

# Start containers with error handling
echo "Starting containers..."
if docker compose -f docker-compose.prod.yml up -d; then
    echo "Application started successfully"
else
    echo "ERROR: Failed to start containers"
    docker compose -f docker-compose.prod.yml logs
    exit 1
fi
